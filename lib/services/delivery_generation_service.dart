// lib/services/delivery_generation_service.dart
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../data/models/delivery_model.dart';
import '../data/models/subscription_model.dart';
import '../data/models/sync_action_model.dart';
import 'connectivity_service.dart';
import 'local_storage_service.dart';

class DeliveryGenerationService extends GetxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();

  String _deliveriesCol(String vid) =>
      '${AppConstants.colVendors}/$vid/${AppConstants.colDeliveries}';

  // ─────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────

  /// Generates deliveries for all active subscriptions whose [effectiveSlots]
  /// contain [targetSlot], scheduled for [date].
  ///
  /// KEY RULE — one delivery per customer+serviceType+slot+day:
  ///   Delivery ID = "{customerId}_{serviceType}_{safeSlot}_{dateKey}"
  ///   If multiple subscription docs exist for the same customer+service+slot,
  ///   their quantities and amounts are SUMMED into a single delivery.
  ///   subscriptionId on the delivery record holds the first matched sub's id
  ///   (used for counter updates only).
  ///
  /// Already-existing deliveries (same ID) are silently skipped — safe to call
  /// multiple times for the same slot+date.
  Future<int> generateForDateAndSlot(
      String vendorId,
      DateTime date,
      String targetSlot, // this is slot.startTime e.g. "06:00"
      ) async {
    final subscriptions = LocalStorageService.getSubscriptions()
        .where((s) => s.isActive)
        .toList();

    if (subscriptions.isEmpty) return 0;

    final customerMap = {
      for (final c in LocalStorageService.getCustomers()) c.id: c,
    };

    // Build a lookup: slot label → startTime and slot startTime → startTime
    // Subscriptions store slot labels; the screen passes startTime.
    // We normalise everything to startTime for comparison.
    final timeSlots = LocalStorageService.getTimeSlots();
    final labelToStartTime = {
      for (final s in timeSlots) s.label: s.startTime,
    };

    /// Returns the startTime for a stored slot string (handles both label and startTime).
    String resolveToStartTime(String slotStr) {
      if (timeSlots.any((s) => s.startTime == slotStr)) return slotStr;
      return labelToStartTime[slotStr] ?? slotStr;
    }

    // ── Group matching subscriptions by customer+serviceType ──────────────
    final Map<String, List<SubscriptionModel>> groups = {};

    for (final sub in subscriptions) {
      if (!sub.shouldDeliverOn(date)) continue;

      // Resolve each stored slot to its startTime, then check if targetSlot matches
      final subStartTimes =
      sub.effectiveSlots.map((s) => resolveToStartTime(s)).toSet();
      if (!subStartTimes.contains(targetSlot)) continue;

      final customer = customerMap[sub.customerId];
      if (customer != null && customer.statusStr == 'inactive') continue;

      final groupKey = '${sub.customerId}__${sub.serviceTypeStr}';
      groups.putIfAbsent(groupKey, () => []).add(sub);
    }

    if (groups.isEmpty) return 0;

    final dateKey  = _dateKey(date);
    final safeSlot = targetSlot.replaceAll(' ', '_').replaceAll(':', '');

    int count = 0;
    final batch          = _db.batch();
    final localToSave    = <DeliveryModel>[];

    for (final entry in groups.entries) {
      final subs  = entry.value;
      final first = subs.first;

      // Deterministic delivery ID — customer+service+slot+date (NOT sub ID)
      final deliveryId =
          '${first.customerId}_${first.serviceTypeStr}_${safeSlot}_$dateKey';

      // Skip if this delivery already exists locally
      if (_existsByDeliveryId(deliveryId)) continue;

      final customer = customerMap[first.customerId];

      // Sum quantity and amount across all merged subscriptions
      final double totalQty =
      subs.fold(0.0, (sum, s) => sum + s.quantity);
      final double totalAmount =
      subs.fold(0.0, (sum, s) => sum + s.pricePerDelivery);

      final delivery = DeliveryModel(
        id:              deliveryId,
        vendorId:        vendorId,
        customerId:      first.customerId,
        customerName:    first.customerName,
        customerAddress: customer?.address ?? '',
        subscriptionId:  first.id, // primary sub — used for counter updates
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
          SetOptions(merge: true), // idempotent — safe if already exists in Firestore
        );
      } else {
        _enqueueOffline(vendorId, delivery);
      }
      count++;
    }

    // Commit Firestore batch
    if (_connectivity.isOnline.value && count > 0) {
      try {
        await batch.commit();
      } catch (e) {
        AppLogger.e('GenerationService: Firestore batch failed — queuing offline', e);
        for (final d in localToSave) {
          _enqueueOffline(vendorId, d.copyWith(isSynced: false));
        }
      }
    }

    // Save to local Hive cache
    for (final d in localToSave) {
      await LocalStorageService.saveDelivery(d);
    }

    AppLogger.i(
        'GenerationService: +$count new deliveries  '
            'slot=$targetSlot  date=$dateKey');
    return count;
  }

  // ─────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────────────────

  /// Check by the merged delivery ID (customer+service+slot+date).
  bool _existsByDeliveryId(String deliveryId) =>
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

  /// Parses "03:00 PM" → DateTime on [baseDate] at 15:00.
  DateTime _slotDateTime(DateTime baseDate, String slot) {
    final parts = slot.trim().toUpperCase().split(' ');
    if (parts.length != 2) {
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 7, 0);
    }
    final tp    = parts[0].split(':');
    int hour    = int.tryParse(tp[0]) ?? 7;
    int minute  = tp.length > 1 ? (int.tryParse(tp[1]) ?? 0) : 0;
    if (parts[1] == 'PM' && hour != 12) hour += 12;
    if (parts[1] == 'AM' && hour == 12) hour = 0;
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }
}