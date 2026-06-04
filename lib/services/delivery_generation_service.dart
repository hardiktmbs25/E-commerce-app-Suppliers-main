// lib/services/delivery_generation_service.dart

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:e_commerce_suppliers/core/constants/app_constants.dart';
import 'package:e_commerce_suppliers/core/utils/logger.dart';
import 'package:e_commerce_suppliers/data/models/delivery_model.dart';
import 'package:e_commerce_suppliers/data/models/subscription_model.dart';
import 'package:e_commerce_suppliers/data/models/sync_action_model.dart';
import 'package:e_commerce_suppliers/services/connectivity_service.dart';
import 'package:e_commerce_suppliers/services/local_storage_service.dart';

class DeliveryGenerationService extends GetxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();

  String _deliveriesCol(String vid) =>
      '${AppConstants.colVendors}/$vid/${AppConstants.colDeliveries}';

  // ─────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────

  /// Creates deliveries for every active subscription that has [targetSlot]
  /// in its effectiveSlots, scheduled for [date].
  ///
  /// Deliveries are keyed on customerId + serviceType + slot + date,
  /// NOT on subscriptionId — so multiple subscriptions for the same customer
  /// at the same slot are merged into a single delivery with summed qty/amount.
  Future<int> generateForDateAndSlot(
      String vendorId,
      DateTime date,
      String targetSlot,
      ) async {
    final subscriptions = LocalStorageService.getSubscriptions()
        .where((s) => s.isActive)
        .toList();

    if (subscriptions.isEmpty) return 0;

    final customerMap = {
      for (final c in LocalStorageService.getCustomers()) c.id: c,
    };

    // ── Group subscriptions by customer + serviceType for this slot/date ──
    final Map<String, List<SubscriptionModel>> groups = {};

    for (final sub in subscriptions) {
      if (!sub.shouldDeliverOn(date)) continue;
      if (!sub.effectiveSlots.contains(targetSlot)) continue;

      final customer = customerMap[sub.customerId];
      if (customer != null && customer.statusStr == 'inactive') continue;

      final groupKey = '${sub.customerId}__${sub.serviceTypeStr}';
      groups.putIfAbsent(groupKey, () => []).add(sub);
    }

    if (groups.isEmpty) return 0;

    int count = 0;
    final batch = _db.batch();
    final List<DeliveryModel> localToSave = [];

    for (final entry in groups.entries) {
      final subs = entry.value;
      final first = subs.first;
      final customer = customerMap[first.customerId];

      final dateKey  = _dateKey(date);
      final safeSlot = targetSlot.replaceAll(' ', '_').replaceAll(':', '');
      final deliveryId =
          '${first.customerId}_${first.serviceTypeStr}_${safeSlot}_$dateKey';

      if (_existsLocally(deliveryId)) continue;

      // Correctly sum quantities and amounts
      final double totalQty = subs.fold(0.0, (s, item) => s + item.quantity);
      final double totalAmount = subs.fold(0.0, (s, item) => s + item.pricePerDelivery);
      
      final String primarySubId = first.id;

      final delivery = DeliveryModel(
        id:              deliveryId,
        vendorId:        vendorId,
        customerId:      first.customerId,
        customerName:    first.customerName,
        customerAddress: customer?.address ?? '',
        subscriptionId:  primarySubId,
        serviceTypeStr:  first.serviceTypeStr,
        quantity:        totalQty,
        unit:            first.unit,
        amount:          totalAmount,
        scheduledDate:   _slotDateTime(date, targetSlot),
        deliverySlot:    targetSlot,
        routeOrder:      0,
        statusStr:       DeliveryStatus.pending.name,
        isExtraOrder:    false,
        isSynced:        _connectivity.isOnline.value,
        createdAt:       DateTime.now(),
        updatedAt:       DateTime.now(),
        billGenerated:   false,
        invoiceId:       null,
      );

      localToSave.add(delivery);

      if (_connectivity.isOnline.value) {
        batch.set(
          _db.collection(_deliveriesCol(vendorId)).doc(delivery.id),
          delivery.toFirestore(),
          SetOptions(merge: true),
        );
      } else {
        _enqueueOffline(vendorId, delivery);
      }
      count++;
    }

    if (_connectivity.isOnline.value && count > 0) {
      try {
        await batch.commit();
      } catch (e) {
        AppLogger.e('GenerationService: batch commit failed — queuing offline', e);
        for (final d in localToSave) {
          _enqueueOffline(vendorId, d.copyWith(isSynced: false));
        }
      }
    }

    for (final d in localToSave) {
      await LocalStorageService.saveDelivery(d);
    }

    if (count > 0) {
      AppLogger.i(
          'GenerationService: +$count deliveries merged for slot=$targetSlot date=${_dateKey(date)}');
    }
    return count;
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  bool _existsLocally(String deliveryId) =>
      LocalStorageService.getDeliveries().any((d) => d.id == deliveryId);

  void _enqueueOffline(String vendorId, DeliveryModel d) {
    LocalStorageService.enqueueSyncAction(SyncActionModel(
      id:            const Uuid().v4(),
      actionTypeStr: SyncActionType.placeExtraOrder.name,
      collection:    _deliveriesCol(vendorId),
      documentId:    d.id,
      payload:       d.toFirestore(),
      createdAt:     DateTime.now(),
    ));
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  DateTime _slotDateTime(DateTime baseDate, String slot) {
    final s = slot.trim().toUpperCase();
    int hour = 7;
    int minute = 0;

    if (s.contains('AM') || s.contains('PM')) {
      final parts = s.split(' ');
      final tp = parts[0].split(':');
      hour   = int.tryParse(tp[0]) ?? 7;
      minute = tp.length > 1 ? (int.tryParse(tp[1]) ?? 0) : 0;
      if (parts[1] == 'PM' && hour != 12) hour += 12;
      if (parts[1] == 'AM' && hour == 12) hour = 0;
    } else {
      final parts = s.split(':');
      hour   = int.tryParse(parts[0]) ?? 7;
      minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    }
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }
}
