import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/service_constants.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/subscription_model.dart';
import '../../../data/models/plan_model.dart';
import '../../../data/models/time_slot_model.dart';
import '../../../data/models/delivery_area_model.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/repositories/global_plan_repository.dart';
import '../../../services/delivery_scheduler_service.dart';
import '../../../services/local_storage_service.dart';
import '../subscriptions_controller.dart' show MergedSubscription;

class SelectedPlanItem {
  final String id;
  final PlanModel plan;

  SelectedPlanItem({
    required this.id,
    required this.plan,
  });
}

class AddSubscriptionController extends GetxController {
  // ─────────────────────────────────────────────────────────────
  // Dependencies
  // ─────────────────────────────────────────────────────────────

  final SubscriptionRepository _repo =
  Get.find<SubscriptionRepository>();

  final GlobalPlanRepository _planRepo =
  Get.put(GlobalPlanRepository());

  // ─────────────────────────────────────────────────────────────
  // Form
  // ─────────────────────────────────────────────────────────────

  final formKey = GlobalKey<FormState>();

  final notesCtrl = TextEditingController();

  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────

  final selectedCustomer = Rxn<CustomerModel>();

  final startDate = DateTime.now().obs;

  final isLoading = false.obs;

  final selectedPlans = <SelectedPlanItem>[].obs;

  final activePlans = <PlanModel>[].obs;

  final timeSlots = <TimeSlotModel>[].obs;

  final deliveryAreas = <DeliveryAreaModel>[].obs;

  final selectedDropdownPlan = Rxn<PlanModel>();

  final Rxn<SubscriptionModel> editingSub = Rxn<SubscriptionModel>();

  /// All subscriptions in the merged group being edited (null in create mode).
  final Rxn<MergedSubscription> editingMerged = Rxn<MergedSubscription>();

  // ─────────────────────────────────────────────────────────────
  // Derived
  // ─────────────────────────────────────────────────────────────


  String? get vendorId =>
      LocalStorageService.getVendor()?.id;

  String get vendorService =>
      LocalStorageService.getVendor()?.serviceTypeStr ??
          ServiceConstants.custom;

  final customers = <CustomerModel>[].obs;

  void _loadCustomers() {
    customers.assignAll(
      LocalStorageService.getCustomers().where((c) => c.isActive).toList(),
    );
  }

  double get totalDeliveryRate {
    return selectedPlans.fold(
      0.0,
          (sum, item) => sum + item.plan.pricePerDelivery,
    );
  }

  double get estimatedMonthlyRevenue {
    return selectedPlans.fold(
      0.0,
          (sum, item) {
        final freq = FrequencyConstants.fromStr(
          item.plan.frequencyStr,
        );

        return sum +
            item.plan.pricePerDelivery *
                FrequencyConstants.monthlyDeliveries(freq);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadCustomers();

    if (Get.arguments is MergedSubscription) {
      final merged = Get.arguments as MergedSubscription;
      editingMerged.value = merged;
      editingSub.value = merged.first; // keep for backward compat checks
      _prefillEditMode(merged);
    } else if (Get.arguments is SubscriptionModel) {
      // Legacy: single sub passed (wrap it)
      final sub = Get.arguments as SubscriptionModel;
      editingSub.value = sub;
      final fakeMerged = MergedSubscription([sub]);
      editingMerged.value = fakeMerged;
      _prefillEditMode(fakeMerged);
    }

    loadPlansAndSlots();
  }

  void _prefillEditMode(MergedSubscription merged) {
    final first = merged.first;
    notesCtrl.text = first.notes ?? '';
    startDate.value = first.startDate;
    selectedCustomer.value = LocalStorageService.getCustomer(first.customerId);

    // For each subscription in the merged group, create a SelectedPlanItem.
    // We first try to match a real active plan; fall back to a mock plan built
    // from the subscription's own values so nothing is ever missing.
    selectedPlans.clear();
    for (final sub in merged.sources) {
      // Try to find the matching plan in already-loaded activePlans.
      // activePlans may not be loaded yet at this point, so we build a
      // provisional mock plan and replace it later in _matchPlansAfterLoad().
      final mockPlan = PlanModel(
        id: 'sub_${sub.id}',
        vendorId: sub.vendorId,
        name: _buildPlanName(sub),
        serviceType: sub.serviceTypeStr,
        frequencyStr: sub.frequencyStr,
        quantity: sub.quantity,
        unit: sub.unit,
        pricePerUnit: sub.pricePerUnit,
        deliverySlotIds: const [],
        deliveryAreaIds: const [],
        createdAt: sub.createdAt,
        updatedAt: sub.updatedAt,
      );
      selectedPlans.add(SelectedPlanItem(id: sub.id, plan: mockPlan));
    }
  }

  String _buildPlanName(SubscriptionModel sub) {
    final freq = sub.frequencyLabel;
    return '${sub.quantity.toStringAsFixed(sub.quantity % 1 == 0 ? 0 : 1)} ${sub.unit} · $freq · ₹${sub.pricePerDelivery.toStringAsFixed(0)}/del';
  }

  /// After plans are loaded from Firestore, replace mock plans with real ones
  /// so the basket shows the actual plan names and full details.
  void _matchPlansAfterLoad() {
    if (editingMerged.value == null) return;
    final merged = editingMerged.value!;
    final updated = <SelectedPlanItem>[];

    for (final sub in merged.sources) {
      // Match by service type + frequency + price
      final real = activePlans.firstWhereOrNull((p) =>
      p.serviceType == sub.serviceTypeStr &&
          p.frequencyStr == sub.frequencyStr &&
          (p.pricePerDelivery - sub.pricePerDelivery).abs() < 0.01
      );
      if (real != null) {
        updated.add(SelectedPlanItem(id: sub.id, plan: real));
      } else {
        // Keep the mock plan built from subscription data
        final existing = selectedPlans.firstWhereOrNull((s) => s.id == sub.id);
        if (existing != null) updated.add(existing);
      }
    }

    if (updated.isNotEmpty) selectedPlans.assignAll(updated);
  }



  // ─────────────────────────────────────────────────────────────
  // Load Plans & Slots
  // ─────────────────────────────────────────────────────────────

  Future<void> loadPlansAndSlots() async {
    if (vendorId == null) return;

    // Load slots
    final slotsResult =
    await _planRepo.fetchTimeSlots(vendorId!);

    slotsResult.fold(
          (failure) {
        Get.snackbar(
          'Error',
          failure.message,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white,
        );
      },
          (list) {
        timeSlots.assignAll(list);
      },
    );

    // Load areas
    final areasResult = await _planRepo.fetchAreas(vendorId!);
    areasResult.fold(
          (failure) {},
          (list) {
        deliveryAreas.assignAll(list);
      },
    );

    // Load plans
    final plansResult =
    await _planRepo.fetchPlans(vendorId!);

    plansResult.fold(
          (failure) {
        Get.snackbar(
          'Error',
          failure.message,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white,
        );
      },
          (list) {
        final filtered = list
            .where(
              (p) =>
          p.isActive &&
              p.serviceType == vendorService,
        )
            .toList();

        activePlans.assignAll(filtered);
        // In edit mode, replace mock plans with real matched plans
        if (editingMerged.value != null) _matchPlansAfterLoad();
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Basket Management
  // ─────────────────────────────────────────────────────────────

  void addPlan(PlanModel plan) {
    if (editingSub.value != null) {
      // In edit mode, replace the single item
      selectedPlans.assignAll([
        SelectedPlanItem(
          id: const Uuid().v4(),
          plan: plan,
        ),
      ]);
    } else {
      selectedPlans.add(
        SelectedPlanItem(
          id: const Uuid().v4(),
          plan: plan,
        ),
      );
    }

    selectedDropdownPlan.value = null;
  }


  void removePlan(String instanceId) {
    selectedPlans.removeWhere(
          (item) => item.id == instanceId,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Date Picker
  // ─────────────────────────────────────────────────────────────

  Future<void> pickStartDate() async {
    final picked = await showDatePicker(
      context: Get.context!,
      initialDate: startDate.value,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(
        const Duration(days: 365),
      ),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      startDate.value = picked;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────

  bool _validateAll() {
    if (vendorId == null) {
      Get.snackbar(
        'Error',
        'Vendor not found.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.error,
        colorText: Colors.white,
      );
      return false;
    }

    if (selectedCustomer.value == null) {
      Get.snackbar(
        '⚠️ Customer Required',
        'Please select a customer.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.error,
        colorText: Colors.white,
      );
      return false;
    }

    if (selectedPlans.isEmpty) {
      Get.snackbar(
        '⚠️ Plan Required',
        'Please add at least one plan.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.error,
        colorText: Colors.white,
      );
      return false;
    }

    return true;
  }

  // ─────────────────────────────────────────────────────────────
  // Save Subscription
  // ─────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (!_validateAll()) return;

    isLoading.value = true;

    final customer = selectedCustomer.value!;

    try {
      if (editingSub.value != null) {
        // ── UPDATE MODE ──────────────────────────────────────────────
        // Update each plan in the basket, matched to the corresponding
        // original subscription in the merged group by position.
        final merged = editingMerged.value;
        final originalSubs = merged?.sources ?? [editingSub.value!];
        int successCount = 0;
        SubscriptionModel? lastUpdated;

        for (int i = 0; i < selectedPlans.length; i++) {
          final item = selectedPlans[i];
          final plan = item.plan;
          // Match to original sub by id (set during prefill) or by position
          final originalSub = originalSubs.firstWhereOrNull((s) => s.id == item.id)
              ?? (i < originalSubs.length ? originalSubs[i] : originalSubs.first);

          final resolvedSlots = plan.deliverySlotIds
              .map((slotId) {
            final slot = timeSlots.firstWhereOrNull((s) => s.id == slotId);
            return slot?.label ?? '07:00 AM';
          }).toList();
          if (resolvedSlots.isEmpty) resolvedSlots.addAll(originalSub.effectiveSlots);
          if (resolvedSlots.isEmpty) resolvedSlots.add('07:00 AM');

          final updatedSub = originalSub.copyWith(
            serviceTypeStr: plan.serviceType,
            frequencyStr: plan.frequencyStr,
            quantity: plan.quantity,
            pricePerUnit: plan.pricePerUnit,
            pricePerDelivery: plan.pricePerDelivery,
            deliverySlots: resolvedSlots,
            notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
            autoResume: true,
          );

          final result = await _repo.updateSubscription(vendorId!, updatedSub);
          result.fold(
                (failure) => Get.snackbar('Error', failure.message, snackPosition: SnackPosition.TOP),
                (_) {
              successCount++;
              lastUpdated = updatedSub;
            },
          );
        }

        if (successCount > 0) {
          Get.back(result: lastUpdated);
          Get.snackbar(
            '✅ Updated',
            '$successCount subscription(s) updated successfully.',
            snackPosition: SnackPosition.TOP,
          );
        }
      } else {
        // ── CREATE MODE ──────────────────────────────────────────────
        int successCount = 0;
        SubscriptionModel? lastSavedSub;

        for (final item in selectedPlans) {
          final plan = item.plan;

          final resolvedSlots = plan.deliverySlotIds
              .map((slotId) {
            final slot = timeSlots.firstWhereOrNull(
                  (s) => s.id == slotId,
            );

            return slot?.label ?? '07:00 AM';
          })
              .toList();

          if (resolvedSlots.isEmpty) {
            resolvedSlots.add('07:00 AM');
          }

          final result = await _repo.createSubscription(
            vendorId: vendorId!,
            customerId: customer.id,
            customerName: customer.name,
            serviceType: plan.serviceType,
            frequency: plan.frequencyStr,
            quantity: plan.quantity,
            unit: plan.unit,
            pricePerUnit: plan.pricePerUnit,
            deliverySlot: resolvedSlots.first,
            deliverySlots: resolvedSlots,
            notes: notesCtrl.text.trim().isEmpty
                ? null
                : notesCtrl.text.trim(),
            startDate: startDate.value,
          );

          await result.fold(
                (failure) async {
              Get.snackbar(
                '❌ Error adding "${plan.name}"',
                failure.message,
                snackPosition: SnackPosition.TOP,
                backgroundColor: AppColors.error,
                colorText: Colors.white,
              );
            },
                (savedSub) async {
              successCount++;
              lastSavedSub = savedSub;

              // Trigger immediate generation for today/tomorrow if applicable
            },
          );
        }

        if (successCount == selectedPlans.length) {
          Get.back(result: lastSavedSub);

          Get.snackbar(
            '✅ Subscription Added',
            '$successCount subscription(s) created successfully.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        }
      }
    } catch (e) {
      Get.snackbar(
        '❌ Error',
        'Something went wrong while saving subscription.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.error,
        colorText: Colors.white,
      );
    } finally {
      isLoading.value = false;
    }
  }


  // ─────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    notesCtrl.dispose();
    super.onClose();
  }
}