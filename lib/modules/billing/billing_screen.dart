// lib/modules/billing/billing_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/shimmer_box.dart';
import '../../widgets/inputs/app_text_field.dart';
import 'billing_controller.dart';

class BillingScreen extends GetView<BillingController> {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Billing',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          actions: [
            Obx(() => IconButton(
              icon: Icon(
                controller.showPaidInOverview.value
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: controller.showPaidInOverview.value
                    ? AppColors.success
                    : null,
              ),
              tooltip: 'Show Paid Bills',
              onPressed: () => controller.showPaidInOverview.toggle(),
            )),
            Obx(() => controller.isGenerating.value
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
                : IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Generate All Monthly Bills',
              onPressed: () => _confirmGenerateAll(context),
            )),
          ],
          bottom: TabBar(
            onTap: (i) => controller.tabIndex.value = i,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Customers'),
              Tab(text: 'Today'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _OverviewTab(ctrl: controller),
            _CustomersTab(ctrl: controller),
            _DailyCollectionTab(ctrl: controller),
          ],
        ),
      ),
    );
  }

  void _confirmGenerateAll(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Generate All Bills?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
            'This will create monthly bills for all active customers '
                'based on their delivered orders this month.',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text('Cancel',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              controller.generateAllMonthlyBills();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Generate',
                style: TextStyle(fontFamily: 'Poppins',
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 0 — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final BillingController ctrl;
  const _OverviewTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingOverview.value) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          const ShimmerBox(height: 100),
          const SizedBox(height: 12),
          const ShimmerBox(height: 80),
          const SizedBox(height: 12),
          const ShimmerBox(height: 80),
        ]);
      }

      return RefreshIndicator(
        onRefresh: () async {
          ctrl.markOverdueBills();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Summary cards ──────────────────────────────────────────
            _SummaryRow(ctrl: ctrl),
            const SizedBox(height: 20),

            // ── Section header ─────────────────────────────────────────
            Row(children: [
              Text(ctrl.showPaidInOverview.value ? 'Paid Bills' : 'Pending Bills',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary, fontFamily: 'Poppins')),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: (ctrl.showPaidInOverview.value ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100)),
                child: Text(ctrl.showPaidInOverview.value ? '${ctrl.paidBills.length}' : '${ctrl.pendingBills.length}',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ctrl.showPaidInOverview.value ? AppColors.success : AppColors.error,
                        fontFamily: 'Poppins')),
              ),
            ]),
            const SizedBox(height: 12),

            if (!ctrl.showPaidInOverview.value && ctrl.pendingBills.isEmpty)
              EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'All Clear!',
                subtitle: 'No pending bills right now. Generate monthly bills to get started.',
                actionLabel: 'Generate Monthly Bills',
                onAction: () => ctrl.generateAllMonthlyBills(),
              )
            else if (ctrl.showPaidInOverview.value && ctrl.paidBills.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No Paid Bills',
                subtitle: 'Collected payments will show up here.',
              )
            else
              ...(ctrl.showPaidInOverview.value ? ctrl.paidBills : ctrl.pendingBills)
                  .map((b) => _BillCard(bill: b, ctrl: ctrl)),
          ],
        ),
      );
    });
  }
}

class _SummaryRow extends StatelessWidget {
  final BillingController ctrl;
  const _SummaryRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Row(children: [
      Expanded(child: _StatCard(
        label: 'Total Pending',
        value: '₹${ctrl.totalPending.value.toStringAsFixed(0)}',
        color: AppColors.error,
        icon: Icons.account_balance_wallet_outlined,
      )),
      const SizedBox(width: 10),
      Expanded(child: _StatCard(
        label: 'Collected Today',
        value: '₹${ctrl.todayCollection.value.toStringAsFixed(0)}',
        color: AppColors.success,
        icon: Icons.payments_outlined,
      )),
      const SizedBox(width: 10),
      Expanded(child: _StatCard(
        label: 'Bills',
        value: '${ctrl.pendingBills.length}',
        color: AppColors.warning,
        icon: Icons.receipt_outlined,
      )),
    ]));
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard(
      {required this.label, required this.value,
        required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [BoxShadow(
            color: AppColors.cardShadow, blurRadius: 6,
            offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                color: color, fontFamily: 'Poppins')),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textHint,
                fontFamily: 'Poppins')),
      ]),
    );
  }
}

class _BillCard extends StatelessWidget {
  final InvoiceModel bill;
  final BillingController ctrl;
  const _BillCard({required this.bill, required this.ctrl});

  Color get _statusColor {
    switch (bill.status) {
      case InvoiceStatus.overdue:  return AppColors.error;
      case InvoiceStatus.partiallyPaid:  return AppColors.warning;
      case InvoiceStatus.paid:     return AppColors.success;
      default:                     return AppColors.info;
    }
  }

  String get _statusLabel {
    switch (bill.status) {
      case InvoiceStatus.overdue:  return 'OVERDUE';
      case InvoiceStatus.partiallyPaid:  return 'PARTIAL';
      case InvoiceStatus.paid:     return 'PAID';
      case InvoiceStatus.sent:     return 'PENDING';
      default:                     return 'DRAFT';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: bill.isOverdue
                    ? AppColors.error.withValues(alpha: 0.3)
                    : AppColors.border,
                width: bill.isOverdue ? 1.5 : 0.8),
            boxShadow: [BoxShadow(
                color: AppColors.cardShadow, blurRadius: 5,
                offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill.customerName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary, fontFamily: 'Poppins')),
                    Text(bill.invoiceNumber,
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textHint, fontFamily: 'Poppins')),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: _statusColor.withValues(alpha: 0.3))),
                child: Text(_statusLabel,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                        color: _statusColor, fontFamily: 'Poppins',
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => ctrl.viewInvoice(bill),
                icon: const Icon(Icons.picture_as_pdf_rounded,
                    size: 20, color: AppColors.primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'View Invoice PDF',
              ),
            ]),
            const Divider(height: 16, color: AppColors.divider),
            Row(children: [
              _BillStat(label: 'Total',    value: '₹${bill.totalAmount.toStringAsFixed(0)}'),
              const SizedBox(width: 16),
              _BillStat(label: 'Deliveries', value: '${bill.totalDeliveries}'),
              const SizedBox(width: 16),
              _BillStat(label: 'Paid',     value: '₹${bill.paidAmount.toStringAsFixed(0)}',
                  color: AppColors.success),
              const SizedBox(width: 16),
              _BillStat(label: 'Pending',  value: '₹${bill.pendingAmount.toStringAsFixed(0)}',
                  color: AppColors.error),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => Get.toNamed(
                    Routes.customerLedger,
                    arguments: {'customerId': bill.customerId,
                      'customerName': bill.customerName}),
                icon: const Icon(Icons.list_alt_rounded, size: 15),
                label: const Text('Ledger',
                    style: TextStyle(fontSize: 12, fontFamily: 'Poppins')),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              )),
              if (bill.pendingAmount > 0) ...[
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => _showPaymentSheet(context, bill),
                  icon: const Icon(Icons.payments_outlined, size: 15,
                      color: Colors.white),
                  label: const Text('Collect',
                      style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                )),
              ],
            ]),
          ]),
        ),
        if (bill.status == InvoiceStatus.paid)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Transform.rotate(
                  angle: -0.2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.4), width: 3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'PAID',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: AppColors.success.withValues(alpha: 0.2),
                        fontFamily: 'Poppins',
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showPaymentSheet(BuildContext ctx, InvoiceModel bill) {
    ctrl.paymentAmountCtrl.text = bill.pendingAmount.toStringAsFixed(0);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        title:        'Collect from ${bill.customerName}',
        maxAmount:    bill.pendingAmount,
        ctrl:         ctrl,
        onConfirm: (amount) => ctrl.recordPaymentForBill(bill, amount),
      ),
    );
  }
}

class _BillStat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _BillStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 10, color: AppColors.textHint,
              fontFamily: 'Poppins')),
      Text(value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary, fontFamily: 'Poppins')),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 1 — CUSTOMERS
// ══════════════════════════════════════════════════════════════════════════

class _CustomersTab extends StatelessWidget {
  final BillingController ctrl;
  const _CustomersTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: AppTextField(
          label: '',
          hint: 'Search customer...',
          prefix: const Icon(Icons.search, size: 18, color: AppColors.textHint),
          onChanged: ctrl.onSearch,
        ),
      ),
      // Filter chips
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          _FilterChip(label: 'All',     val: 'all',     ctrl: ctrl),
          const SizedBox(width: 8),
          _FilterChip(label: 'Pending', val: 'pending', ctrl: ctrl),
          const SizedBox(width: 8),
          _FilterChip(label: 'Overdue', val: 'overdue', ctrl: ctrl),
          const SizedBox(width: 8),
          _FilterChip(label: 'Paid',    val: 'paid',    ctrl: ctrl),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(child: Obx(() {
        if (ctrl.filteredCustomers.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: const EmptyState(
                icon: Icons.people_outline,
                title: 'No Customers Found',
                subtitle: 'Try changing the filter.',
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: ctrl.filteredCustomers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _CustomerBillingTile(
              customer: ctrl.filteredCustomers[i], ctrl: ctrl),
        );
      })),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label, val;
  final BillingController ctrl;
  const _FilterChip(
      {required this.label, required this.val, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ctrl.setFilter(val),
      child: Obx(() {
        final isSelected = ctrl.filterStatus.value == val;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                  color: isSelected ? Colors.white : AppColors.textSecondary)),
        );
      }),
    );
  }
}

class _CustomerBillingTile extends StatelessWidget {
  final CustomerModel customer;
  final BillingController ctrl;
  const _CustomerBillingTile(
      {required this.customer, required this.ctrl});

  Color get _color => customer.pendingAmount > 0
      ? AppColors.error : AppColors.success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _color.withValues(alpha: 0.1),
          child: Text(customer.name[0].toUpperCase(),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: _color, fontFamily: 'Poppins')),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary, fontFamily: 'Poppins')),
              Text(customer.phone,
                  style: const TextStyle(fontSize: 11,
                      color: AppColors.textHint, fontFamily: 'Poppins')),
            ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${customer.pendingAmount.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: _color, fontFamily: 'Poppins')),
          Text(customer.pendingAmount > 0 ? 'PENDING' : 'CLEAR',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: _color, fontFamily: 'Poppins')),
        ]),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded,
              size: 18, color: AppColors.textHint),
          onSelected: (v) {
            if (v == 'collect') {
              _showCollect(context);
            } else if (v == 'bill') {
              ctrl.generateMonthlyBill(customer);
            } else if (v == 'ledger') {
              Get.toNamed(Routes.customerLedger, arguments: {
                'customerId': customer.id,
                'customerName': customer.name,
              });
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'collect',
                child: Text('Collect Payment')),
            const PopupMenuItem(value: 'bill',
                child: Text('Generate Bill')),
            const PopupMenuItem(value: 'ledger',
                child: Text('View Ledger')),
          ],
        ),
      ]),
    );
  }

  void _showCollect(BuildContext ctx) {
    ctrl.paymentAmountCtrl.text =
        customer.pendingAmount.toStringAsFixed(0);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        title:     'Collect from ${customer.name}',
        maxAmount: customer.pendingAmount,
        ctrl:      ctrl,
        onConfirm: (amount) async {
          ctrl.paymentAmountCtrl.text = amount.toString();
          await ctrl.quickCollect(customer);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 2 — DAILY COLLECTION
// ══════════════════════════════════════════════════════════════════════════

class _DailyCollectionTab extends StatelessWidget {
  final BillingController ctrl;
  const _DailyCollectionTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingDaily.value) {
        return const Center(child: CircularProgressIndicator());
      }

      return Column(children: [
        // Today's collection summary
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: AppColors.gradientGreen,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.payments_outlined, color: Colors.white, size: 28),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Collected Today',
                  style: TextStyle(fontSize: 12, color: Colors.white70,
                      fontFamily: 'Poppins')),
              Text('₹${ctrl.todayCollection.value.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 26,
                      fontWeight: FontWeight.w900, color: Colors.white,
                      fontFamily: 'Poppins')),
            ]),
            const Spacer(),
            Text('${ctrl.todayPayments.length} payments',
                style: const TextStyle(fontSize: 12,
                    color: Colors.white70, fontFamily: 'Poppins')),
          ]),
        ),

        // Unpaid customers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('Unpaid Customers',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary, fontFamily: 'Poppins')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100)),
              child: Text('${ctrl.dailyCollectionCustomers.length}',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, color: AppColors.error,
                      fontFamily: 'Poppins')),
            ),
          ]),
        ),
        const SizedBox(height: 8),

        if (ctrl.dailyCollectionCustomers.isEmpty)
          const Expanded(child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'All Collected!',
                subtitle: 'No unpaid customers today.',
              ),
            ),
          ))
        else
          Expanded(child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: ctrl.dailyCollectionCustomers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = ctrl.dailyCollectionCustomers[i];
              return _DailyCollectionTile(customer: c, ctrl: ctrl);
            },
          )),
      ]);
    });
  }
}

class _DailyCollectionTile extends StatelessWidget {
  final CustomerModel customer;
  final BillingController ctrl;
  const _DailyCollectionTile(
      {required this.customer, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.error.withValues(alpha: 0.1),
          child: Text(customer.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.error, fontFamily: 'Poppins')),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary, fontFamily: 'Poppins')),
              Text('₹${customer.pendingAmount.toStringAsFixed(0)} pending',
                  style: const TextStyle(fontSize: 12,
                      color: AppColors.error, fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            ])),
        ElevatedButton(
          onPressed: () {
            ctrl.paymentAmountCtrl.text =
                customer.pendingAmount.toStringAsFixed(0);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _PaymentSheet(
                title: 'Collect from ${customer.name}',
                maxAmount: customer.pendingAmount,
                ctrl: ctrl,
                onConfirm: (amount) async {
                  ctrl.paymentAmountCtrl.text = amount.toString();
                  await ctrl.quickCollect(customer);
                },
              ),
            );
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success, elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          child: const Text('Collect',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: Colors.white, fontFamily: 'Poppins')),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PAYMENT BOTTOM SHEET  (shared across all tabs)
// ══════════════════════════════════════════════════════════════════════════

class _PaymentSheet extends StatelessWidget {
  final String title;
  final double maxAmount;
  final BillingController ctrl;
  final Future<void> Function(double) onConfirm;

  const _PaymentSheet({
    required this.title,
    required this.maxAmount,
    required this.ctrl,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, fontFamily: 'Poppins')),
          Text('Max: ₹${maxAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12,
                  color: AppColors.textHint, fontFamily: 'Poppins')),
          const SizedBox(height: 18),

          // Amount
          AppTextField(
            label: 'Amount (₹)',
            hint: maxAmount.toStringAsFixed(0),
            controller: ctrl.paymentAmountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            ],
            prefix: const Icon(Icons.currency_rupee_rounded,
                size: 18, color: AppColors.textHint),
          ),
          const SizedBox(height: 14),

          // Payment method
          const Text('Payment Method',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, fontFamily: 'Poppins')),
          const SizedBox(height: 8),
          Obx(() => Row(
            children: BillingController.paymentMethods.map((m) {
              final isSelected = ctrl.selectedPayMethod.value == m;
              return Expanded(child: GestureDetector(
                onTap: () => ctrl.selectedPayMethod.value = m,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(
                    BillingController.paymentMethodLabels[m]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: isSelected
                            ? Colors.white : AppColors.textSecondary),
                  ),
                ),
              ));
            }).toList(),
          )),
          const SizedBox(height: 14),

          // Note
          AppTextField(
            label: 'Note (optional)',
            hint: 'e.g. Cash received at door',
            controller: ctrl.paymentNoteCtrl,
          ),
          const SizedBox(height: 22),

          Obx(() => PrimaryButton(
            label: 'Record Payment',
            onTap: () {
              final amt =
                  double.tryParse(ctrl.paymentAmountCtrl.text) ?? 0;
              if (amt <= 0) {
                Get.snackbar('Invalid', 'Enter a valid amount.',
                    snackPosition: SnackPosition.TOP);
                return;
              }
              onConfirm(amt);
            },
            isLoading: ctrl.isRecordingPayment.value,
            color: AppColors.success,
            icon: Icons.check_circle_outline_rounded,
          )),
        ],
      ),
    );
  }
}
