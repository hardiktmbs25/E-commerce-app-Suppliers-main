// lib/modules/deliveries/deliveries_controller.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/logger.dart';
import '../../data/models/delivery_model.dart';
import '../../data/models/time_slot_model.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../data/repositories/global_plan_repository.dart';
import '../../routes/app_routes.dart';
import '../../services/delivery_scheduler_service.dart';
import '../../services/local_storage_service.dart';

/// A merged view of deliveries that share the same customer + service +
/// delivery slot + scheduled date. Their quantities and amounts are summed.
class MergedDelivery {
  final List<DeliveryModel> sources;
  MergedDelivery(this.sources) : assert(sources.isNotEmpty);

  DeliveryModel get first => sources.first;

  String get id              => first.id; // primary id for actions on single
  String get customerId      => first.customerId;
  String get customerName    => first.customerName;
  String get customerAddress => first.customerAddress;
  String get serviceTypeStr  => first.serviceTypeStr;
  String get deliverySlot    => first.deliverySlot;
  String get statusStr       => first.statusStr;
  DateTime get scheduledDate => first.scheduledDate;

  double get quantity => sources.fold(0.0, (s, d) => s + d.quantity);
  String get unit     => first.unit;
  double get amount   => sources.fold(0.0, (s, d) => s + d.amount);

  bool get isPending   => first.isPending;
  bool get isDelivered => first.isDelivered;
  bool get isMissed    => first.isMissed;
  bool get isToday     => first.isToday;
}

class DeliveriesController extends GetxController {
  // ─────────────────────────────────────────────────────────────
  // Dependencies
  // ─────────────────────────────────────────────────────────────

  final DeliveryRepository _repo = Get.find<DeliveryRepository>();
  final DeliverySchedulerService _scheduler = Get.find<DeliverySchedulerService>();

  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────

  final RxList<DeliveryModel> allDeliveries       = <DeliveryModel>[].obs;
  final RxList<DeliveryModel> filteredDeliveries   = <DeliveryModel>[].obs;
  /// Filtered deliveries with duplicates (same customer+slot+date+service) merged.
  final RxList<MergedDelivery> mergedDeliveries    = <MergedDelivery>[].obs;
  final RxList<TimeSlotModel> availableTimeSlots   = <TimeSlotModel>[].obs;

  final RxString statusFilter = 'all'.obs;
  final RxString searchQuery  = ''.obs;
  final RxString slotFilter   = ''.obs;

  final RxBool isLoading    = true.obs;
  final RxBool isGenerating = false.obs;
  final RxString markingId  = ''.obs;

  final searchCtrl = TextEditingController();

  StreamSubscription? _deliverySub;
  StreamSubscription? _slotsSub;
  Timer? _loadingTimeout;

  // ─────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────

  String? get vendorId => LocalStorageService.getVendor()?.id;

  // Counts are based on mergedDeliveries so they match exactly what the
  // screen shows (one row per customer+service+slot+day group).
  int get deliveredCount => mergedDeliveries.where((d) => d.isDelivered).length;
  int get pendingCount   => mergedDeliveries.where((d) => d.isPending).length;
  int get missedCount    => mergedDeliveries.where((d) => d.isMissed).length;

  double get totalAmount =>
      mergedDeliveries.fold(0.0, (sum, d) => sum + d.amount);

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();

    ever(statusFilter, (_) => _applyFilter());
    ever(searchQuery,  (_) => _applyFilter());
    ever(slotFilter,   (_) => _applyFilter());

    _loadAvailableTimeSlots();

    // Seed from local cache so screen isn't blank
    final cached = LocalStorageService.getTodayDeliveries();
    if (cached.isNotEmpty) {
      allDeliveries.assignAll(cached);
      _applyFilter();
      isLoading.value = false;
    }

    _loadingTimeout = Timer(const Duration(seconds: 8), () {
      if (isLoading.value) {
        isLoading.value = false;
        AppLogger.w('DeliveriesController: loading timeout');
      }
    });
  }

  @override
  void onReady() {
    super.onReady();
    _initStream();
    _autoGenerateToday();
  }

  Future<void> _autoGenerateToday() async {
    // Wait a brief moment to ensure time slots are loaded from Hive
    if (availableTimeSlots.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    if (vendorId == null || availableTimeSlots.isEmpty) return;

    // Auto-generate for the current/closest slot if not already done
    final now = DateTime.now();
    final currentSlot = availableTimeSlots.firstWhereOrNull((s) {
      final end = s.getEndDateTime(now);
      return now.isBefore(end);
    }) ?? availableTimeSlots.first;

    AppLogger.i('DeliveriesController: auto-triggering generation for slot ${currentSlot.startTime}');
    final count = await _scheduler.generateForSlots(vendorId!, [currentSlot.startTime]);
    
    if (count > 0) {
      final updated = LocalStorageService.getTodayDeliveries();
      allDeliveries.assignAll(updated);
      _applyFilter();
    }
  }

  @override
  void onClose() {
    _loadingTimeout?.cancel();
    _deliverySub?.cancel();
    _slotsSub?.cancel();
    searchCtrl.dispose();
    super.onClose();
  }

  // ─────────────────────────────────────────────────────────────
  // Stream
  // ─────────────────────────────────────────────────────────────

  void _initStream() {
    if (vendorId == null) { isLoading.value = false; return; }

    _deliverySub = _repo.watchTodayDeliveries(vendorId!).listen(
          (list) {
        _loadingTimeout?.cancel();
        allDeliveries.assignAll(list);
        _applyFilter();
        isLoading.value = false;
      },
      onError: (e) {
        _loadingTimeout?.cancel();
        AppLogger.e('Deliveries stream error', e);
        final cached = LocalStorageService.getTodayDeliveries();
        allDeliveries.assignAll(cached);
        _applyFilter();
        isLoading.value = false;
        Get.snackbar('Offline Mode', 'Showing cached deliveries.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: AppColors.warning,
            colorText: Colors.white);
      },
      cancelOnError: false,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Time slot helpers
  // ─────────────────────────────────────────────────────────────

  void _loadAvailableTimeSlots() {
    // 1. Seed immediately from Hive cache so the picker shows without waiting
    _applySlotList(LocalStorageService.getTimeSlots());

    // 2. Subscribe to Firestore stream so newly added slots appear live
    //    and Hive stays in sync for future screen opens
    if (vendorId == null) return;
    _slotsSub = Get.find<GlobalPlanRepository>()
        .watchTimeSlots(vendorId!)
        .listen((slots) {
      LocalStorageService.saveTimeSlots(slots);   // keep Hive fresh
      _applySlotList(slots);
    });
  }

  void _applySlotList(List<TimeSlotModel> slots) {
    final active = slots.where((s) => s.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    availableTimeSlots.assignAll(active);
  }

  void clearSlotFilter() => slotFilter.value = '';

  // ─────────────────────────────────────────────────────────────
  // Manual generation
  // ─────────────────────────────────────────────────────────────

  /// Called from the slot-picker bottom sheet.
  /// [selectedSlots] — list of startTime strings the vendor chose.
  Future<void> generateForSlots(List<String> selectedSlots) async {
    if (vendorId == null || selectedSlots.isEmpty) return;

    isGenerating.value = true;
    try {
      final count = await _scheduler.generateForSlots(vendorId!, selectedSlots);
      if (count > 0) {
        // Refresh local list in case we are offline or stream is slow
        final updated = LocalStorageService.getTodayDeliveries();
        allDeliveries.assignAll(updated);
        _applyFilter();

        Get.snackbar(
          '✅ Generated',
          '$count deliveries created for ${selectedSlots.length} slot(s).',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.success,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Nothing New',
          'All deliveries for the selected slot(s) already exist.',
          snackPosition: SnackPosition.TOP,
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Could not generate deliveries.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white);
    } finally {
      isGenerating.value = false;
    }
  }

  /// Marks pending deliveries missed if their slot window has closed.
  Future<void> markMissed() async {
    if (vendorId == null) return;
    await _scheduler.markExpiredAsMissed(vendorId!);
  }

  // ─────────────────────────────────────────────────────────────
  // Refresh
  // ─────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    await markMissed();
    final cached = LocalStorageService.getTodayDeliveries();
    allDeliveries.assignAll(cached);
    _applyFilter();
    await _deliverySub?.cancel();
    _initStream();
  }

  // ─────────────────────────────────────────────────────────────
  // Filter
  // ─────────────────────────────────────────────────────────────

  void _applyFilter() {
    var list = allDeliveries.toList();

    if (statusFilter.value != 'all') {
      list = list.where((d) => d.statusStr == statusFilter.value).toList();
    }

    if (slotFilter.value.isNotEmpty) {
      list = list.where((d) => d.deliverySlot == slotFilter.value).toList();
    }

    final q = searchQuery.value.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((d) =>
      d.customerName.toLowerCase().contains(q) ||
          d.customerAddress.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    filteredDeliveries.assignAll(list);

    // ── Build merged deliveries ─────────────────────────────────────────────
    // Two deliveries merge when: customerId + serviceTypeStr + deliverySlot
    // + scheduledDate (day) are all equal. Qty and amount are summed.
    final merged = <MergedDelivery>[];
    for (final d in list) {
      final dayKey = '${d.scheduledDate.year}-${d.scheduledDate.month}-${d.scheduledDate.day}';
      final key = '${d.customerId}__${d.serviceTypeStr}__${d.deliverySlot}__$dayKey';
      final existing = merged.where((m) =>
      '${m.customerId}__${m.serviceTypeStr}__${m.deliverySlot}__${m.scheduledDate.year}-${m.scheduledDate.month}-${m.scheduledDate.day}' == key
      ).firstOrNull;
      if (existing != null) {
        existing.sources.add(d);
      } else {
        merged.add(MergedDelivery([d]));
      }
    }
    mergedDeliveries.assignAll(merged);
  }

  void onSearchChanged(String value) => searchQuery.value = value;
  void clearSearch() { searchCtrl.clear(); searchQuery.value = ''; }

  // ─────────────────────────────────────────────────────────────
  // Mark Delivery
  // ─────────────────────────────────────────────────────────────

  Future<void> markDelivery(
      DeliveryModel delivery,
      DeliveryStatus status, {
        String? notes,
      }) async {
    if (vendorId == null) return;
    markingId.value = delivery.id;

    final result = await _repo.updateDeliveryStatus(
        vendorId!, delivery, status, notes: notes);

    result.fold(
          (failure) => Get.snackbar('Error', failure.message,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white),
          (_) {
        final label = status == DeliveryStatus.delivered
            ? '✅ Delivered'
            : status == DeliveryStatus.missed
            ? '❌ Missed'
            : 'Updated';
        Get.snackbar(label, '${delivery.customerName} updated.',
            snackPosition: SnackPosition.TOP);
      },
    );

    markingId.value = '';
  }

  void showMarkWithNotesDialog(DeliveryModel delivery, DeliveryStatus status) {
    final notesCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(status == DeliveryStatus.missed ? 'Reason for Missing' : 'Add Notes'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter notes...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            Get.back();
            markDelivery(delivery, status,
                notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
          },
          child: Text(status == DeliveryStatus.missed ? 'Mark Missed' : 'Confirm'),
        ),
      ],
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // Bulk
  // ─────────────────────────────────────────────────────────────

  Future<void> markAllDelivered() async {
    if (vendorId == null) return;
    final pending = allDeliveries.where((d) => d.isPending).toList();
    if (pending.isEmpty) return;
    for (final d in pending) {
      await _repo.updateDeliveryStatus(vendorId!, d, DeliveryStatus.delivered);
    }
    Get.snackbar('✅ Updated', '${pending.length} deliveries marked delivered.',
        snackPosition: SnackPosition.TOP);
  }

  // ─────────────────────────────────────────────────────────────
  // Delete
  // ─────────────────────────────────────────────────────────────

  Future<void> deleteDelivery(DeliveryModel delivery) async {
    if (delivery.status != DeliveryStatus.delivered) {
      Get.snackbar('Not Allowed', 'Only delivered deliveries can be deleted.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.warning,
          colorText: Colors.white);
      return;
    }
    try {
      await _repo.deleteDelivery(vendorId!, delivery.id);
      Get.snackbar('Deleted', 'Delivery removed.',
          snackPosition: SnackPosition.TOP);
    } catch (_) {
      Get.snackbar('Error', 'Failed to delete.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────

  void goToAddDelivery()   => Get.toNamed(Routes.addDelivery);
  void goToExtraOrder()    => Get.toNamed(Routes.extraOrder);
  void goToHistory()       => Get.toNamed(Routes.deliveryHistory);
  void goToDetail(DeliveryModel d) => Get.toNamed(Routes.deliveryDetail, arguments: d);
}