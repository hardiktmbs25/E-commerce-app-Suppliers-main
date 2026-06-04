// lib/data/repositories/delivery_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'package:e_commerce_suppliers/core/constants/app_constants.dart';
import 'package:e_commerce_suppliers/core/errors/failures.dart';
import 'package:e_commerce_suppliers/core/utils/logger.dart';
import 'package:e_commerce_suppliers/services/connectivity_service.dart';
import 'package:e_commerce_suppliers/services/customer_balance_service.dart';
import 'package:e_commerce_suppliers/services/ledger_service.dart';
import 'package:e_commerce_suppliers/services/local_storage_service.dart';
import 'package:e_commerce_suppliers/data/models/delivery_model.dart';
import 'package:e_commerce_suppliers/data/models/ledger_entry_model.dart';
import 'package:e_commerce_suppliers/data/models/sync_action_model.dart';

class DeliveryRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();

  String _col(String vendorId) =>
      '${AppConstants.colVendors}/$vendorId/${AppConstants.colDeliveries}';

  String _subscriptionsCol(String vid) =>
      '${AppConstants.colVendors}/$vid/${AppConstants.colSubscriptions}';

  // ── Today's deliveries stream ─────────────────────────────────────────────
  Stream<List<DeliveryModel>> watchTodayDeliveries(String vendorId) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end   = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return _db
        .collection(_col(vendorId))
        .where('scheduledDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledDate',
        isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('scheduledDate')
        .orderBy('routeOrder')
        .snapshots()
        .map((snap) {
      final deliveries =
      snap.docs.map((d) => DeliveryModel.fromFirestore(d)).toList();
      LocalStorageService.saveDeliveries(deliveries);
      return deliveries;
    })
        .handleError((e) {
      AppLogger.e('watchTodayDeliveries error', e);
      return LocalStorageService.getTodayDeliveries();
    });
  }

  List<DeliveryModel> getLocalTodayDeliveries() =>
      LocalStorageService.getTodayDeliveries();

  // ── Pending deliveries stream ─────────────────────────────────────────────
  Stream<List<DeliveryModel>> watchPendingDeliveries(String vendorId) {
    return _db
        .collection(_col(vendorId))
        .where('status', isEqualTo: DeliveryStatus.pending.name)
        .snapshots()
        .map((snap) {
      final deliveries = snap.docs.map((d) => DeliveryModel.fromFirestore(d)).toList();
      LocalStorageService.saveDeliveries(deliveries);
      return deliveries;
    }).handleError((e) {
      AppLogger.e('watchPendingDeliveries error', e);
      return LocalStorageService.getDeliveries()
          .where((d) => d.status == DeliveryStatus.pending)
          .toList();
    });
  }

  // ── Mark delivery status ──────────────────────────────────────────────────
  Future<Result<void>> updateDeliveryStatus(
      String vendorId,
      DeliveryModel delivery,
      DeliveryStatus newStatus, {
        String? notes,
      }) async {
    final now     = DateTime.now();
    final updated = delivery.copyWith(
      statusStr:   newStatus.name,
      deliveredAt: newStatus == DeliveryStatus.delivered ? now : null,
      notes:       notes,
      isSynced:    _connectivity.isOnline.value,
    );

    // 1. Update local cache immediately for instant UI feedback
    await LocalStorageService.saveDelivery(updated);

    // 1b. Create instant ledger entry for delivered items (Post-charge)
    if (newStatus == DeliveryStatus.delivered) {
      final ledger = Get.find<LedgerService>();
      await ledger.createEntry(
        vendorId: vendorId,
        customerId: delivery.customerId,
        type: LedgerEntryType.charge,
        amount: delivery.amount,
        description: 'Delivery: ${delivery.serviceTypeStr} (${delivery.quantity} ${delivery.unit})',
        referenceId: delivery.id,
      );

      // Update customer balance instantly
      await Get.find<CustomerBalanceService>().recalculateCustomerBalance(
        vendorId: vendorId,
        customerId: delivery.customerId,
      );
    }

    final payload = {
      'status':      newStatus.name,
      'deliveredAt': newStatus == DeliveryStatus.delivered
          ? now.toIso8601String()
          : null,
      'notes':       notes,
      'updatedAt':   now.toIso8601String(),
    };

    if (_connectivity.isOnline.value) {
      try {
        final batch = _db.batch();

        batch.update(
          _db.collection(_col(vendorId)).doc(delivery.id),
          {
            'status':      newStatus.name,
            'deliveredAt': newStatus == DeliveryStatus.delivered
                ? FieldValue.serverTimestamp()
                : null,
            'notes':       notes,
            'updatedAt':   FieldValue.serverTimestamp(),
          },
        );

        if (newStatus == DeliveryStatus.delivered && delivery.subscriptionId != null) {
          batch.update(
            _db
                .collection(_subscriptionsCol(vendorId))
                .doc(delivery.subscriptionId!),
            {
              'completedDeliveries': FieldValue.increment(1),
              'updatedAt':           FieldValue.serverTimestamp(),
            },
          );

          final subs = LocalStorageService.getSubscriptions();
          final sub = subs.firstWhereOrNull((s) => s.id == delivery.subscriptionId);
          if (sub != null) {
            await LocalStorageService.saveSubscription(sub.copyWith(
              completedDeliveries: sub.completedDeliveries + 1,
            ));
          }
        }

        await batch.commit();
        await LocalStorageService.saveDelivery(
            updated.copyWith(isSynced: true));

        AppLogger.i('Delivery ${delivery.id} => ${newStatus.name}');
        return const Result.success(null);
      } catch (e) {
        AppLogger.e('updateDeliveryStatus error — queuing offline', e);
        await _enqueueMarkDelivery(vendorId, delivery.id, payload);
        return const Result.success(null);
      }
    } else {
      await _enqueueMarkDelivery(vendorId, delivery.id, payload);
      AppLogger.i('Delivery ${delivery.id} queued offline');
      return const Result.success(null);
    }
  }

  // ── Place extra order ─────────────────────────────────────────────────────
  Future<Result<DeliveryModel>> placeExtraOrder({
    required String vendorId,
    required String customerId,
    required String customerName,
    required String customerAddress,
    required String serviceType,
    required double quantity,
    required String unit,
    required double amount,
    String? notes,
  }) async {
    final id  = const Uuid().v4();
    final now = DateTime.now();
    final delivery = DeliveryModel(
      id:              id,
      vendorId:        vendorId,
      customerId:      customerId,
      customerName:    customerName,
      customerAddress: customerAddress,
      serviceTypeStr:  serviceType,
      quantity:        quantity,
      unit:            unit,
      amount:          amount,
      scheduledDate:   now,
      isExtraOrder:    true,
      notes:           notes,
      createdAt:       now,
      updatedAt:       now,
    );

    await LocalStorageService.saveDelivery(delivery);

    // Create instant ledger entry for extra orders
    final ledger = Get.find<LedgerService>();
    await ledger.createEntry(
      vendorId: vendorId,
      customerId: customerId,
      type: LedgerEntryType.extra,
      amount: amount,
      description: 'Extra Order: $serviceType ($quantity $unit)',
      referenceId: id,
    );

    // Update customer balance instantly
    await Get.find<CustomerBalanceService>().recalculateCustomerBalance(
      vendorId: vendorId,
      customerId: customerId,
    );

    if (_connectivity.isOnline.value) {
      await _db
          .collection(_col(vendorId))
          .doc(id)
          .set(delivery.toFirestore());
    } else {
      await _enqueuePlaceExtraOrder(vendorId, id, delivery);
    }

    return Result.success(delivery);
  }

  // ── History (paginated) ───────────────────────────────────────────────────
  Future<Result<List<DeliveryModel>>> fetchDeliveryHistory(
      String vendorId, {
        DateTime? startDate,
        DateTime? endDate,
        String? customerId,
        String? status,
        DocumentSnapshot? lastDoc,
      }) async {
    try {
      var query = _db
          .collection(_col(vendorId))
          .orderBy('scheduledDate', descending: true)
          .limit(AppConstants.pageSize);

      if (startDate != null) {
        query = query.where('scheduledDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('scheduledDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      if (customerId != null) {
        query = query.where('customerId', isEqualTo: customerId);
      }
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snap = await query.get();
      return Result.success(
          snap.docs.map((d) => DeliveryModel.fromFirestore(d)).toList());
    } catch (e) {
      AppLogger.e('fetchDeliveryHistory error', e);
      return Result.failure(FirestoreFailure(e.toString()));
    }
  }

  // ── Sync queue helpers ────────────────────────────────────────────────────

  Future<void> _enqueueMarkDelivery(
      String vendorId, String deliveryId, Map<String, dynamic> payload) async {
    final action = SyncActionModel(
      id:            const Uuid().v4(),
      actionTypeStr: SyncActionType.markDelivery.name,
      collection:    _col(vendorId),
      documentId:    deliveryId,
      payload:       payload,
      createdAt:     DateTime.now(),
    );
    await LocalStorageService.enqueueSyncAction(action);
  }

  Future<void> _enqueuePlaceExtraOrder(
      String vendorId, String id, DeliveryModel d) async {
    final action = SyncActionModel(
      id:            const Uuid().v4(),
      actionTypeStr: SyncActionType.placeExtraOrder.name,
      collection:    _col(vendorId),
      documentId:    id,
      payload:       d.toFirestore(),
      createdAt:     DateTime.now(),
    );
    await LocalStorageService.enqueueSyncAction(action);
  }

  // ── Delete delivery ────────────────────────────────────────────────────────

  Future<Result<void>> deleteDelivery(
      String vendorId,
      String deliveryId,
      ) async {
    try {
      if (_connectivity.isOnline.value) {
        await _db
            .collection(_col(vendorId))
            .doc(deliveryId)
            .delete();
      } else {
        AppLogger.w('deleteDelivery: offline, removing from local cache only');
      }

      final allDeliveries = LocalStorageService.getDeliveries();
      final remaining = allDeliveries.where((d) => d.id != deliveryId).toList();
      await LocalStorageService.clearDeliveries();
      await LocalStorageService.saveDeliveries(remaining);

      AppLogger.i('Delivery deleted => $deliveryId');
      return const Result.success(null);
    } catch (e) {
      AppLogger.e('deleteDelivery error', e);
      return Result.failure(FirestoreFailure(e.toString()));
    }
  }
}