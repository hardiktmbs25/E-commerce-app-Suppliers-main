// lib/modules/deliveries/history/delivery_history_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/extensions.dart';
import '../../../data/models/delivery_model.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/shimmer_box.dart';
import 'delivery_history_controller.dart';

class DeliveryHistoryScreen extends StatelessWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DeliveryHistoryController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Delivery History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: ctrl.showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          /// Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: ctrl.searchCtrl,
              onChanged: ctrl.onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by customer name...',
                hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                ),
                suffixIcon: Obx(() {
                  return ctrl.searchQuery.value.isNotEmpty
                      ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                    ),
                    onPressed: ctrl.clearSearch,
                  )
                      : const SizedBox();
                }),
                contentPadding:
                const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
              ),
            ),
          ),

          /// Active Filters
          Obx(() {
            if (ctrl.activeFilterLabel.isEmpty) {
              return const SizedBox(height: 8);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: AppColors.primary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_alt_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ctrl.activeFilterLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: ctrl.clearFilters,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),

          /// List
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading.value) {
                return const ShimmerList(itemHeight: 80);
              }

              if (ctrl.deliveries.isEmpty) {
                return EmptyState(
                  title: 'No Delivery History',
                  subtitle:
                  'Past deliveries will appear here.',
                  icon: Icons.history_rounded,
                  actionLabel:
                  ctrl.hasFilters ? 'Clear Filters' : null,
                  onAction:
                  ctrl.hasFilters ? ctrl.clearFilters : null,
                );
              }

              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollEndNotification &&
                      n.metrics.extentAfter < 100 &&
                      !ctrl.isFetchingMore.value &&
                      ctrl.hasMore.value) {
                    ctrl.loadMore();
                  }

                  return false;
                },
                child: ListView.separated(
                  padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: ctrl.deliveries.length +
                      (ctrl.isFetchingMore.value ? 1 : 0),
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    if (i == ctrl.deliveries.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    final d = ctrl.deliveries[i];

                    return _HistoryCard(
                      delivery: d,
                      onTap: () => Get.toNamed(
                        Routes.deliveryDetail,
                        arguments: d,
                      ),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final DeliveryModel delivery;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.delivery,
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
            color: AppColors.border,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                delivery.isDelivered
                    ? Icons.check_circle_rounded
                    : delivery.isMissed
                    ? Icons.cancel_rounded
                    : Icons.local_shipping_rounded,
                color: statusColor,
                size: 20,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    delivery.customerName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Poppins',
                    ),
                  ),

                  Text(
                    delivery.scheduledDate.formatted,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontFamily: 'Poppins',
                    ),
                  ),

                  if (delivery.isExtraOrder)
                    const Text(
                      '⚡ Extra Order',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF8B5CF6),
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment:
              CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${delivery.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontFamily: 'Poppins',
                  ),
                ),

                const SizedBox(height: 4),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                    statusColor.withValues(alpha: 0.1),
                    borderRadius:
                    BorderRadius.circular(100),
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
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
