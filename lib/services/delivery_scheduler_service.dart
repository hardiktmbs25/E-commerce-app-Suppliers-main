// lib/services/delivery_scheduler_service.dart
import 'package:get/get.dart';
import '../core/utils/logger.dart';
import '../data/models/delivery_model.dart';
import '../data/repositories/delivery_repository.dart';
import 'local_storage_service.dart';
import 'delivery_generation_service.dart';

/// Manual-only scheduler — no background timers.
///
/// The vendor picks slots on the Deliveries screen and taps "Generate".
///
/// Date logic:
///   • If we have NOT yet generated for today → generates for TODAY.
///   • If today is already done → generates for TOMORROW.
///   This lets the vendor pre-generate the next day's deliveries without
///   duplicating today's.
class DeliverySchedulerService extends GetxService {
  static const _kLastGeneratedKey = 'last_generated_date';

  final RxBool isGenerating = false.obs;

  // ─────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────

  /// Generate deliveries for [selectedSlots].
  /// Returns total number of new delivery records created.
  Future<int> generateForSlots(
      String vendorId,
      List<String> selectedSlots,
      ) async {
    if (selectedSlots.isEmpty) return 0;

    isGenerating.value = true;
    int total = 0;

    try {
      final targetDate = _resolveTargetDate();
      AppLogger.i('Scheduler: Generating for ${_dateKey(targetDate)}');

      for (final slot in selectedSlots) {
        AppLogger.i('Scheduler: slot=$slot');
        total += await Get.find<DeliveryGenerationService>()
            .generateForDateAndSlot(vendorId, targetDate, slot);
      }

      // Always record the target date as generated.
      // If total==0 it means everything was already created (idempotent skip),
      // so we still advance the key so the next tap moves to the following day.
      await LocalStorageService.saveSetting(
        _kLastGeneratedKey,
        _dateKey(targetDate),
      );

      if (total > 0) {
        AppLogger.i('Scheduler: Generated $total deliveries for ${_dateKey(targetDate)}');
      } else {
        AppLogger.i('Scheduler: All deliveries already exist for ${_dateKey(targetDate)} — advancing date');
      }
    } catch (e) {
      AppLogger.e('Scheduler: generateForSlots failed', e);
    } finally {
      isGenerating.value = false;
    }

    return total;
  }

  /// The date deliveries will be generated for on the NEXT Generate tap.
  /// Use this to show "Generating for: Today / Tomorrow" in the UI.
  DateTime get nextGenerationDate => _resolveTargetDate();

  /// Mark pending deliveries as missed once their slot window has closed.
  Future<void> markExpiredAsMissed(String vendorId) async {
    final now        = DateTime.now();
    final deliveries = LocalStorageService.getTodayDeliveries();
    final timeSlots  = LocalStorageService.getTimeSlots();
    final repo       = Get.find<DeliveryRepository>();

    for (final delivery in deliveries) {
      if (delivery.status != DeliveryStatus.pending) continue;

      final slotModel =
      timeSlots.firstWhereOrNull((s) => s.startTime == delivery.deliverySlot);

      final missedAfter = slotModel != null
          ? slotModel.getEndDateTime(delivery.scheduledDate)
          : delivery.scheduledDate.add(const Duration(hours: 2));

      if (now.isAfter(missedAfter)) {
        AppLogger.i(
          'Scheduler: Marking missed — ${delivery.customerName} '
              '(slot ${delivery.deliverySlot})',
        );
        await repo.updateDeliveryStatus(
            vendorId, delivery, DeliveryStatus.missed);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────

  /// Today if not yet generated today, tomorrow otherwise.
  DateTime _resolveTargetDate() {
    final today         = DateTime.now();
    final todayKey      = _dateKey(today);
    final lastGenerated =
    LocalStorageService.getSetting<String>(_kLastGeneratedKey);

    if (lastGenerated == todayKey) {
      return today.add(const Duration(days: 1));
    }
    return today;
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}