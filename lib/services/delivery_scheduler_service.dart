// lib/services/delivery_scheduler_service.dart
import 'package:get/get.dart';
import '../core/utils/logger.dart';
import '../data/models/delivery_model.dart';
import '../data/repositories/delivery_repository.dart';
import 'local_storage_service.dart';
import 'delivery_generation_service.dart';

/// Manual-only scheduler.
///
/// No background timers. No auto-generation.
/// The vendor explicitly picks a time slot on the Deliveries screen and taps
/// "Generate" — this service creates the deliveries for that slot.
///
/// Date advancement logic:
/// - First tap of the day → generates for TODAY.
/// - Every subsequent tap on the same calendar day → generates for TOMORROW
///   (i.e. the next date that has not yet been generated for these slots).
/// - This prevents the same day being flooded with duplicates while still
///   allowing the vendor to pre-generate the next day's deliveries.
class DeliverySchedulerService extends GetxService {

  static const _kLastGeneratedDateKey = 'last_generated_date';

  final RxBool isGenerating = false.obs;

  // ─────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────

  /// Generate deliveries for [selectedSlots] (list of startTime strings like
  /// "07:00 AM").
  ///
  /// Picks the target date automatically:
  ///   - If we have NOT yet generated for today → use today.
  ///   - If we already generated for today → use tomorrow.
  ///
  /// Returns the total number of new deliveries created.
  Future<int> generateForSlots(
      String vendorId,
      List<String> selectedSlots,
      ) async {
    if (selectedSlots.isEmpty) return 0;

    isGenerating.value = true;
    int total = 0;
    try {
      final targetDate = _resolveTargetDate();
      AppLogger.i('Scheduler: Target date → ${_dateKey(targetDate)}');

      for (final slotStartTime in selectedSlots) {
        AppLogger.i('Scheduler: Generating for slot $slotStartTime on ${_dateKey(targetDate)}');
        total += await Get.find<DeliveryGenerationService>()
            .generateForDateAndSlot(vendorId, targetDate, slotStartTime);
      }

      if (total > 0) {
        // Record that we have generated for this date
        await LocalStorageService.saveSetting(
          _kLastGeneratedDateKey,
          _dateKey(targetDate),
        );
        AppLogger.i(
            'Scheduler: Generated $total deliveries across '
                '${selectedSlots.length} slot(s) for ${_dateKey(targetDate)}');
      } else {
        AppLogger.i('Scheduler: Nothing new to generate for ${_dateKey(targetDate)}');
      }
    } catch (e) {
      AppLogger.e('Scheduler: generateForSlots failed', e);
    } finally {
      isGenerating.value = false;
    }
    return total;
  }

  /// The date for which generation will run next time the vendor taps Generate.
  /// Useful for displaying "Generating for: Today / Tomorrow" in the UI.
  DateTime get nextGenerationDate => _resolveTargetDate();

  /// Mark pending deliveries as missed once their slot window has closed.
  /// Call this when the vendor opens the screen or taps "Mark Missed".
  Future<void> markExpiredAsMissed(String vendorId) async {
    final now          = DateTime.now();
    final deliveries   = LocalStorageService.getTodayDeliveries();
    final timeSlots    = LocalStorageService.getTimeSlots();
    final deliveryRepo = Get.find<DeliveryRepository>();

    for (final delivery in deliveries) {
      if (delivery.status != DeliveryStatus.pending) continue;

      final slotModel = timeSlots
          .firstWhereOrNull((s) => s.startTime == delivery.deliverySlot);

      final missedAfter = slotModel != null
          ? slotModel.getEndDateTime(delivery.scheduledDate)
          : delivery.scheduledDate.add(const Duration(hours: 2));

      if (now.isAfter(missedAfter)) {
        AppLogger.i(
          'Scheduler: Marking missed — ${delivery.customerName} '
              '(slot ${delivery.deliverySlot})',
        );
        await deliveryRepo.updateDeliveryStatus(
            vendorId, delivery, DeliveryStatus.missed);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────

  /// Returns today if we haven't generated for today yet, otherwise tomorrow.
  DateTime _resolveTargetDate() {
    final today           = DateTime.now();
    final todayKey        = _dateKey(today);
    final lastGeneratedKey =
    LocalStorageService.getSetting<String>(_kLastGeneratedDateKey);

    if (lastGeneratedKey == todayKey) {
      // Already generated for today → advance to tomorrow
      return today.add(const Duration(days: 1));
    }
    return today;
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}