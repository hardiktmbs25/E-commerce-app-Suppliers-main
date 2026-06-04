// lib/modules/deliveries/deliveries_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../data/models/delivery_model.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/shimmer_box.dart';
import 'deliveries_controller.dart';

class DeliveriesScreen extends StatelessWidget {
  const DeliveriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DeliveriesController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today\'s Deliveries'),
            Text(
              DateTime.now().formatted,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
        actions: [
          // History button
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Delivery History',
            onPressed: ctrl.goToHistory,
          ),
          // Mark All button
          Obx(
            () => ctrl.pendingCount > 0
                ? TextButton.icon(
                    onPressed: ctrl.markAllDelivered,
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text(
                      'Mark All',
                      style: TextStyle(fontSize: 12, fontFamily: 'Poppins'),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.success,
                    ),
                  )
                : const SizedBox(),
          ),
        ],
      ),
      floatingActionButton: Obx(
        () => FloatingActionButton.extended(
          heroTag: 'fab_deliveries',
          onPressed: ctrl.isGenerating.value
              ? null
              : () => _showSlotPicker(context, ctrl),
          backgroundColor: ctrl.isGenerating.value
              ? AppColors.border
              : AppColors.primary,
          icon: ctrl.isGenerating.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(
            ctrl.isGenerating.value ? 'Generating...' : 'Generate',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        color: AppColors.primary,
        child: Obx(() {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Summary Bar
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryItem(
                            'Total',
                            '${ctrl.mergedDeliveries.length}',
                            AppColors.primary,
                          ),
                          _Divider(),
                          _SummaryItem(
                            'Delivered',
                            '${ctrl.deliveredCount}',
                            AppColors.success,
                          ),
                          _Divider(),
                          _SummaryItem(
                            'Pending',
                            '${ctrl.pendingCount}',
                            AppColors.warning,
                          ),
                          _Divider(),
                          _SummaryItem(
                            'Missed',
                            '${ctrl.missedCount}',
                            AppColors.error,
                          ),
                        ],
                      ),
                    ),

                    // Search
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: ctrl.searchCtrl,
                        onChanged: ctrl.onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search by customer or address...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: ctrl.searchQuery.value.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: ctrl.clearSearch,
                                )
                              : null,
                        ),
                      ),
                    ),

                    // Status Filters
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              [
                                'all',
                                'pending',
                                'delivered',
                                'missed',
                                'cancelled',
                              ].map((f) {
                                final selected = ctrl.statusFilter.value == f;

                                return GestureDetector(
                                  onTap: () => ctrl.statusFilter.value = f,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      f.toCapitalCase,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Slot Chips
                    if (ctrl.availableTimeSlots.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _SlotChip(
                                label: 'All Slots',
                                isSelected: ctrl.slotFilter.value.isEmpty,
                                onTap: ctrl.clearSlotFilter,
                                icon: Icons.access_time_rounded,
                              ),
                              ...ctrl.availableTimeSlots.map(
                                (slot) => _SlotChip(
                                  label: slot.label,
                                  isSelected:
                                      ctrl.slotFilter.value == slot.startTime,
                                  onTap: () =>
                                      ctrl.slotFilter.value = slot.startTime,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),

              // Loading
              if (ctrl.isLoading.value)
                const SliverToBoxAdapter(child: ShimmerList(itemHeight: 90))
              // Empty State
              else if (ctrl.filteredDeliveries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyState(
                      title: ctrl.searchQuery.value.isNotEmpty
                          ? 'No Results Found'
                          : 'No Deliveries Today',
                      subtitle:
                          'Deliveries are auto-generated from active subscriptions.',
                      icon: Icons.local_shipping_outlined,
                    ),
                  ),
                )
              // Delivery List
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final merged = ctrl.mergedDeliveries[i];
                      final d = merged.first;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Slidable(
                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            children: [
                              if (merged.isPending) ...[
                                SlidableAction(
                                  onPressed: (_) => ctrl.markDelivery(
                                    d,
                                    DeliveryStatus.delivered,
                                  ),
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  icon: Icons.check_circle,
                                  label: 'Delivered',
                                ),
                                SlidableAction(
                                  onPressed: (_) =>
                                      ctrl.showMarkWithNotesDialog(
                                        d,
                                        DeliveryStatus.missed,
                                      ),
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  icon: Icons.cancel,
                                  label: 'Missed',
                                ),
                              ],
                            ],
                          ),
                          child: _DeliveryCard(
                            delivery: d,
                            mergedAmount: merged.amount,
                            mergedQuantity: merged.quantity,
                            mergedCount: merged.sources.length,
                            isMarking: ctrl.markingId.value == d.id,
                            onMarkDelivered: () =>
                                ctrl.markDelivery(d, DeliveryStatus.delivered),
                            onMarkMissed: () => ctrl.showMarkWithNotesDialog(
                              d,
                              DeliveryStatus.missed,
                            ),
                            onTap: () => ctrl.goToDetail(d),
                          ),
                        ),
                      );
                    }, childCount: ctrl.mergedDeliveries.length),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Slot Picker Bottom Sheet
  // ─────────────────────────────────────────────────────────────

  void _showSlotPicker(BuildContext context, DeliveriesController ctrl) {
    if (ctrl.availableTimeSlots.isEmpty) {
      Get.snackbar(
        'No Time Slots',
        'Please add time slots in Profile → Time Slots first.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.warning,
        colorText: Colors.white,
      );
      return;
    }

    final selected = <String>{}.obs;

    Get.bottomSheet(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      Obx(
        () => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                'Select Time Slot(s)',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Deliveries will be created for all active subscriptions matching the selected slot.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 20),

              // Slot tiles
              ...ctrl.availableTimeSlots.map((slot) {
                final isSelected = selected.contains(slot.startTime);
                return GestureDetector(
                  onTap: () {
                    if (isSelected) {
                      selected.remove(slot.startTime);
                    } else {
                      selected.add(slot.startTime);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                slot.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                slot.startTime,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),

              // Generate button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          Get.back();
                          await ctrl.generateForSlots(selected.toList());
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.border,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    selected.isEmpty
                        ? 'Select a slot to continue'
                        : 'Generate for ${selected.length} slot${selected.length > 1 ? "s" : ""}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final DeliveryModel delivery;
  final double mergedAmount;
  final double mergedQuantity;
  final int mergedCount;
  final bool isMarking;
  final VoidCallback onMarkDelivered;
  final VoidCallback onMarkMissed;
  final VoidCallback onTap;

  const _DeliveryCard({
    required this.delivery,
    required this.mergedAmount,
    required this.mergedQuantity,
    required this.mergedCount,
    required this.isMarking,
    required this.onMarkDelivered,
    required this.onMarkMissed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = Color(delivery.statusColor);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: delivery.isPending
                ? AppColors.warning.withValues(alpha: 0.3)
                : delivery.isDelivered
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.error.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: isMarking
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: statusColor,
                            ),
                          )
                        : Icon(
                            Icons.local_shipping_rounded,
                            color: statusColor,
                            size: 20,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              delivery.customerName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          if (delivery.isExtraOrder)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8B5CF6,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                '⚡ Extra',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8B5CF6),
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          if (mergedCount > 1)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                '$mergedCount plans',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        delivery.customerAddress,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${mergedAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        delivery.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ],
            ),
            // Notes preview
            if (delivery.notes != null && delivery.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 12,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        delivery.notes!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (delivery.isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: '✅ Delivered',
                      color: AppColors.success,
                      onTap: onMarkDelivered,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      label: '❌ Missed',
                      color: AppColors.error,
                      onTap: onMarkMissed,
                    ),
                  ),
                ],
              ),
            ],
            if (delivery.deliveredAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Delivered at ${delivery.deliveredAt!.timeOnly}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            if (!delivery.isSynced)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 11,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Pending sync',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.warning,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final Color color;

  const _SummaryItem(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'Poppins',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 32, width: 0.8, color: AppColors.border);
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const _SlotChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.schedule_rounded,
              size: 13,
              color: isSelected ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }
}