// lib/modules/customers/detail/customer_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/extensions.dart';
import '../../../data/models/invoice_model.dart';
import '../../../data/models/customer_model.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/common/shimmer_box.dart';
import 'customer_detail_controller.dart';

class CustomerDetailScreen extends GetView<CustomerDetailController> {
  const CustomerDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.customer.value?.name ?? 'Customer')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: controller.editCustomer,
          ),
        ],
      ),
      body: Obx(() {
        final c = controller.customer.value;
        if (c == null) return const Center(child: CircularProgressIndicator());
        return CustomScrollView(
          slivers: [
            // Profile header
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.gradientPurple,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(c.name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white, fontFamily: 'Poppins')),
                    ),
                    const SizedBox(height: 12),
                    Text(c.name,
                        style: const TextStyle(fontSize: 20,
                            fontWeight: FontWeight.w700, color: Colors.white,
                            fontFamily: 'Poppins')),
                    Text(c.phone,
                        style: TextStyle(fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontFamily: 'Poppins')),
                    const SizedBox(height: 20),
                    // Wallet section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Wallet Balance', style: TextStyle(color: Colors.white, fontSize: 12)),
                              Text('₹${c.walletBalance.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.white, size: 30),
                            onPressed: () => _showAddWalletDialog(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatChip('Delivered', '${controller.deliveredThisMonth}', Colors.white),
                        _StatChip('Missed', '${controller.missedThisMonth}', Colors.white),
                        _StatChip('Pending ₹',
                            c.pendingAmount.toStringAsFixed(0), Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Info section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Customer Info',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary, fontFamily: 'Poppins')),
                    const SizedBox(height: 14),
                    _InfoRow(Icons.location_on_outlined, 'Address', c.address),
                    if (c.landmark != null)
                      _InfoRow(Icons.place_outlined, 'Landmark', c.landmark!),
                    _InfoRow(Icons.category_outlined, 'Service',
                        c.serviceTypeStr.toCapitalCase),
                    if (c.notes != null)
                      _InfoRow(Icons.notes_rounded, 'Notes', c.notes!),
                    if (c.routeName != null)
                      _InfoRow(Icons.route_outlined, 'Route', c.routeName!),
                    _InfoRow(Icons.calendar_today_outlined, 'Customer Since',
                        c.createdAt.formatted),
                    const SizedBox(height: 20),

                    // Action buttons
                    PrimaryButton(
                      label: c.status == CustomerStatus.paused ? 'Resume Deliveries' : 'Pause Deliveries',
                      onTap: controller.togglePause,
                      icon: c.status == CustomerStatus.paused ? Icons.play_arrow : Icons.pause,
                      color: c.status == CustomerStatus.paused ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'Generate Monthly Bill',
                      onTap: controller.generateBill,
                      isLoading: controller.isGeneratingBill.value,
                      icon: Icons.receipt_long_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'Add Delivery',
                      onTap: controller.goToAddDelivery,
                      icon: Icons.add_circle_outline_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Call Customer',
                      onTap: () {},
                      icon: Icons.phone_outlined,
                    ),
                  ],
                ),
              ),
            ),

            // Invoice history
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text('Invoice History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary, fontFamily: 'Poppins')),
              ),
            ),

            if (controller.isLoading.value)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: List.generate(3, (_) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ShimmerBox(height: 80),
                        ),
                    ),
                  ),
                ),
              )
            else if (controller.invoices.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No invoices yet.',
                      style: TextStyle(fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFamily: 'Poppins')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (_, i) {
                      final inv = controller.invoices[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inv.isOverdue
                                ? AppColors.error.withValues(alpha: 0.3)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(inv.invoiceNumber,
                                style: const TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Poppins')),
                            Text('${inv.monthName} ${inv.year}',
                                style: const TextStyle(fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Poppins')),
                          ]),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 20, color: AppColors.primary),
                            onPressed: () => controller.viewInvoice(inv),
                            tooltip: 'View PDF',
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_outlined, size: 20, color: AppColors.primary),
                            onPressed: () => controller.shareInvoice(inv),
                            tooltip: 'Share',
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₹${inv.totalAmount.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Poppins')),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: inv.status == InvoiceStatus.paid
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                inv.statusStr.toUpperCase(),
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                                    color: inv.status == InvoiceStatus.paid
                                        ? AppColors.success : AppColors.warning,
                                    fontFamily: 'Poppins'),
                              ),
                            ),
                          ]),
                        ]),
                      );
                    },
                    childCount: controller.invoices.length,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
  void _showAddWalletDialog(BuildContext context) {
    final amountController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Add Money to Wallet'),
        content: TextField(
          controller: amountController,
          decoration: const InputDecoration(labelText: 'Amount (₹)', hintText: 'Enter amount'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                controller.addMoneyToWallet(amount);
                Get.back();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
          color: color, fontFamily: 'Poppins')),
      Text(label, style: TextStyle(fontSize: 11,
          color: color.withValues(alpha: 0.8), fontFamily: 'Poppins')),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppColors.textHint),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11,
              color: AppColors.textHint, fontFamily: 'Poppins')),
          Text(value, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w500, color: AppColors.textPrimary,
              fontFamily: 'Poppins')),
        ])),
      ]),
    );
  }
}