// lib/modules/subscriptions/subscriptions_controller.dart
import 'dart:async';
import 'package:get/get.dart';
import '../../data/models/subscription_model.dart';
import '../../data/repositories/subscription_repository.dart';
import '../../services/auth_service.dart';
import '../../services/local_storage_service.dart';
import '../../core/utils/logger.dart';

/// A merged view of one or more subscriptions that share the same
/// customer + service type + frequency + delivery slots.
/// Duplicate entries (same timing) are collapsed into one card whose
/// price is the sum of all individual prices.
class MergedSubscription {
  final List<SubscriptionModel> sources; // all raw subs that were merged

  MergedSubscription(this.sources) : assert(sources.isNotEmpty);

  SubscriptionModel get first => sources.first;

  String get customerId    => first.customerId;
  String get customerName  => first.customerName;
  String get serviceTypeStr => first.serviceTypeStr;
  String get frequencyStr   => first.frequencyStr;
  String get statusStr      => first.statusStr;
  DateTime get startDate    => first.startDate;
  String? get notes         => first.notes;

  List<String> get effectiveSlots => first.effectiveSlots;

  double get quantity => sources.fold(0.0, (s, m) => s + m.quantity);
  String get unit     => first.unit;

  /// Sum of all merged pricePerDelivery values.
  double get pricePerDelivery =>
      sources.fold(0.0, (s, m) => s + m.pricePerDelivery);

  double get estimatedMonthlyRevenue =>
      sources.fold(0.0, (s, m) => s + m.estimatedMonthlyRevenue);

  bool get isActive => first.isActive;
  bool get isPaused => first.isPaused;

  String get frequencyLabel => first.frequencyLabel;
}

class SubscriptionsController extends GetxController {
  final SubscriptionRepository _repo = Get.find<SubscriptionRepository>();

  final RxList<SubscriptionModel> allSubs      = <SubscriptionModel>[].obs;
  final RxList<SubscriptionModel> filteredSubs = <SubscriptionModel>[].obs;
  /// Keyed by customerId → list of MERGED subscription groups to display.
  final RxMap<String, List<MergedSubscription>> groupedSubs =
      <String, List<MergedSubscription>>{}.obs;
  final RxString statusFilter = 'all'.obs;
  final RxString searchQuery  = ''.obs;
  final RxBool   isLoading    = true.obs;

  String? get vendorId => AuthService.to.uid;
  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    final cached = LocalStorageService.getSubscriptions();
    allSubs.assignAll(cached);
    if (cached.isNotEmpty) {
      isLoading.value = false;
    }
    _applyFilter();
    debounce(searchQuery, (_) => _applyFilter(), time: const Duration(milliseconds: 300));
    ever(statusFilter, (_) => _applyFilter());
  }


  @override
  void onReady() {
    super.onReady();
    _initStream();
  }

  void _initStream() {
    final uid = vendorId;
    if (uid == null) {
      isLoading.value = false;
      return;
    }

    _sub = _repo.watchSubscriptions(uid).listen(
          (subs) {
        allSubs.assignAll(subs);
        _applyFilter();
        isLoading.value = false;
      },
      onError: (e) {
        AppLogger.e('Subscriptions stream error', e);
        isLoading.value = false;
      },
    );
  }


  void _applyFilter() {
    var result = allSubs.toList();
    if (statusFilter.value != 'all') {
      result = result.where((s) => s.statusStr == statusFilter.value).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      result = result.where((s) =>
      s.customerName.toLowerCase().contains(q) ||
          s.serviceTypeStr.toLowerCase().contains(q)).toList();
    }
    filteredSubs.assignAll(result);

    // ── Group by customer, then merge duplicates within each customer ────
    // Two subs are "duplicates" if they share: serviceType + frequency + slots.
    // Their prices and quantities are summed into one MergedSubscription card.
    final Map<String, List<MergedSubscription>> groups = {};
    for (final sub in result) {
      if (!groups.containsKey(sub.customerId)) {
        groups[sub.customerId] = [];
      }
      final slotKey = (sub.effectiveSlots.toList()..sort()).join('|');
      final mergeKey = '${sub.serviceTypeStr}__${sub.frequencyStr}__$slotKey';

      final existing = groups[sub.customerId]!
          .where((m) => _mergeKey(m.first) == mergeKey)
          .firstOrNull;

      if (existing != null) {
        existing.sources.add(sub);
      } else {
        groups[sub.customerId]!.add(MergedSubscription([sub]));
      }
    }
    groupedSubs.assignAll(groups);
  }

  String _mergeKey(SubscriptionModel s) {
    final slotKey = (s.effectiveSlots.toList()..sort()).join('|');
    return '${s.serviceTypeStr}__${s.frequencyStr}__$slotKey';
  }

  Future<void> togglePause(SubscriptionModel sub) async {
    if (vendorId == null) return;

    if (sub.isActive) {
      await _repo.pauseSubscription(vendorId!, sub.id, null);
    } else {
      await _repo.resumeSubscription(vendorId!, sub.id);
    }

    Get.snackbar(
      sub.isActive ? '⏸ Paused' : '▶ Resumed',
      '${sub.customerName}\'s subscription ${sub.isActive ? 'paused' : 'resumed'}.',
      snackPosition: SnackPosition.TOP,
    );
  }

  /// Pause/resume all subs in a merged group.
  Future<void> togglePauseMerged(MergedSubscription merged) async {
    if (vendorId == null) return;
    for (final sub in merged.sources) {
      if (sub.isActive) {
        await _repo.pauseSubscription(vendorId!, sub.id, null);
      } else {
        await _repo.resumeSubscription(vendorId!, sub.id);
      }
    }
    Get.snackbar(
      merged.isActive ? '⏸ Paused' : '▶ Resumed',
      '${merged.customerName}\'s subscription ${merged.isActive ? 'paused' : 'resumed'}.',
      snackPosition: SnackPosition.TOP,
    );
  }

  Future<void> cancelSubscription(SubscriptionModel sub) async {
    if (vendorId == null) return;
    await _repo.cancelSubscription(vendorId!, sub.id);
  }

  /// Cancel all subs in a merged group.
  Future<void> cancelMerged(MergedSubscription merged) async {
    if (vendorId == null) return;
    for (final sub in merged.sources) {
      await _repo.cancelSubscription(vendorId!, sub.id);
    }
  }


  // Computed
  int get activeCount   => allSubs.where((s) => s.isActive).length;
  int get pausedCount   => allSubs.where((s) => s.isPaused).length;
  double get totalMonthlyRevenue =>
      allSubs.where((s) => s.isActive)
          .fold(0.0, (total, s) => total + s.estimatedMonthlyRevenue);

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}