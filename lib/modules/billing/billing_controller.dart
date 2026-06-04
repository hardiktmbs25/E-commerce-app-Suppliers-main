// lib/modules/billing/billing_controller.dart
//
// Central controller for the entire billing module.
// Tab structure: Overview | Customers | Daily Collection
//
// Depends on:
//   BillingService   – all business logic
//   BillingRepository – Firestore streams
//   LocalStorageService – offline cache reads

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/utils/logger.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/repositories/billing_repository.dart';
import '../../services/billing_service.dart';
import '../../services/local_storage_service.dart';
import '../../data/repositories/customer_repository.dart';
import '../../services/pdf_service.dart';
import 'package:printing/printing.dart';

class BillingController extends GetxController {
  final BillingRepository _repo    = Get.find<BillingRepository>();
  final BillingService    _billing = Get.find<BillingService>();
  final PdfService        _pdf     = Get.find<PdfService>();

  // ── Tab ───────────────────────────────────────────────────────────────
  final RxInt tabIndex = 0.obs;

  // ── Vendor ────────────────────────────────────────────────────────────
  String? get vendorId => LocalStorageService.getVendor()?.id;

  // ── Overview stats (live from Firestore streams) ──────────────────────
  final RxList<InvoiceModel> pendingBills   = <InvoiceModel>[].obs;
  final RxList<InvoiceModel> paidBills      = <InvoiceModel>[].obs;
  final RxBool   showPaidInOverview         = false.obs;
  final RxDouble totalPending               = 0.0.obs;
  final RxDouble totalPaid                  = 0.0.obs;
  final RxDouble todayCollection            = 0.0.obs;
  final RxBool   isLoadingOverview          = true.obs;

  // ── Customer list (billing tab) ───────────────────────────────────────
  final RxList<CustomerModel> allCustomers  = <CustomerModel>[].obs;
  final RxList<CustomerModel> filteredCustomers = <CustomerModel>[].obs;
  final RxString searchQuery               = ''.obs;
  final RxString filterStatus              = 'all'.obs; // all|pending|overdue|paid

  // ── Daily collection (today's unpaid customers) ───────────────────────
  final RxList<CustomerModel> dailyCollectionCustomers = <CustomerModel>[].obs;
  final RxList<PaymentModel>  todayPayments            = <PaymentModel>[].obs;
  final RxBool   isLoadingDaily                        = true.obs;

  // ── Bill generation ───────────────────────────────────────────────────
  final RxBool isGenerating = false.obs;

  // ── Payment dialog state ──────────────────────────────────────────────
  final RxBool   isRecordingPayment = false.obs;
  final paymentAmountCtrl           = TextEditingController();
  final paymentNoteCtrl             = TextEditingController();
  final RxString selectedPayMethod  = 'cash'.obs;

  StreamSubscription? _pendingSub;
  StreamSubscription? _paidSub;
  StreamSubscription? _todayPaySub;
  StreamSubscription? _customerSub;

  // ── Payment method options ─────────────────────────────────────────────
  static const paymentMethods = ['cash', 'upi', 'online', 'cheque', 'other'];
  static const paymentMethodLabels = {
    'cash':   'Cash',
    'upi':    'UPI',
    'online': 'Online',
    'cheque': 'Cheque',
    'other':  'Other',
  };

  // ══════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════

  @override
  void onInit() {
    super.onInit();
    _loadCustomers();
    _initStreams();
    // React to search / filter changes
    debounce(searchQuery, (_) => _applyFilter(), time: const Duration(milliseconds: 300));
    ever(filterStatus, (_) => _applyFilter());
  }

  void _loadCustomers() {
    final customers = LocalStorageService.getCustomers()
        .where((c) => c.isActive)
        .toList()
      ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
    allCustomers.assignAll(customers);
    filteredCustomers.assignAll(customers);
    _buildDailyCollection(customers);

    // Pre-fill pending bills from local storage cache
    final localBills = LocalStorageService.getBills()
        .where((b) => b.status != InvoiceStatus.paid)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    pendingBills.assignAll(localBills);
    totalPending.value = localBills.fold(0.0, (s, b) => s + b.pendingAmount);
    totalPaid.value    = localBills.fold(0.0, (s, b) => s + b.paidAmount);
  }

  void _initStreams() {
    if (vendorId == null) {
      isLoadingOverview.value = false;
      isLoadingDaily.value    = false;
      return;
    }

    _pendingSub = _repo.watchPendingInvoices(vendorId!).listen(
          (bills) {
        pendingBills.assignAll(bills);
        totalPending.value = bills.fold(0.0, (s, b) => s + b.pendingAmount);
        totalPaid.value    = bills.fold(0.0, (s, b) => s + b.paidAmount);
        isLoadingOverview.value = false;
      },
      onError: (e) {
        AppLogger.e('BillingController pendingBills stream', e);
        isLoadingOverview.value = false;
      },
    );

    _paidSub = _repo.watchPaidInvoices(vendorId!).listen(
          (bills) {
        paidBills.assignAll(bills);
      },
      onError: (e) => AppLogger.e('BillingController paidBills stream', e),
    );

    _todayPaySub = _repo.watchTodayPayments(vendorId!).listen(
          (payments) {
        todayPayments.assignAll(payments);
        todayCollection.value = payments.fold(0.0, (s, p) => s + p.amount);
        isLoadingDaily.value  = false;
      },
      onError: (e) {
        AppLogger.e('BillingController todayPayments stream', e);
        isLoadingDaily.value = false;
      },
    );

    final customerRepo = Get.find<CustomerRepository>();
    _customerSub = customerRepo.watchCustomers(vendorId!).listen(
          (list) {
        final active = list.where((c) => c.isActive).toList()
          ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
        allCustomers.assignAll(active);
        _applyFilter();
        _buildDailyCollection(active);
      },
      onError: (e) => AppLogger.e('BillingController customer watch error', e),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // FILTER
  // ══════════════════════════════════════════════════════════════════════

  void onSearch(String q) => searchQuery.value = q;

  void setFilter(String status) => filterStatus.value = status;

  void _applyFilter() {
    var list = List<CustomerModel>.from(allCustomers);

    // Text search
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) =>
      c.name.toLowerCase().contains(q) ||
          c.phone.contains(q)).toList();
    }

    // Status filter
    switch (filterStatus.value) {
      case 'pending':
        list = list.where((c) => c.pendingAmount > 0).toList();
        break;
      case 'overdue':
        list = list.where((c) => c.paymentStatusStr == 'overdue').toList();
        break;
      case 'paid':
        list = list.where((c) => c.pendingAmount <= 0).toList();
        break;
    }

    filteredCustomers.assignAll(list);
  }

  // ══════════════════════════════════════════════════════════════════════
  // DAILY COLLECTION
  // ══════════════════════════════════════════════════════════════════════

  void _buildDailyCollection(List<CustomerModel> customers) {
    dailyCollectionCustomers.assignAll(
      customers.where((c) => c.pendingAmount > 0).toList()
        ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PAYMENT RECORDING
  // ══════════════════════════════════════════════════════════════════════

  /// Quick collect — called from Daily Collection tab.
  Future<void> quickCollect(CustomerModel customer) async {
    if (vendorId == null) return;
    final amount = double.tryParse(paymentAmountCtrl.text);
    if (amount == null || amount <= 0) {
      Get.snackbar('Invalid Amount', 'Please enter a valid amount.',
          snackPosition: SnackPosition.TOP);
      return;
    }
    if (amount > customer.pendingAmount) {
      Get.snackbar(
        'Too Much',
        'Payment ₹${amount.toStringAsFixed(0)} exceeds '
            'pending ₹${customer.pendingAmount.toStringAsFixed(0)}.',
        snackPosition: SnackPosition.TOP,
      );
      return;
    }

    isRecordingPayment.value = true;

    final ok = await _billing.recordPayment(
      vendorId:         vendorId!,
      customerId:       customer.id,
      customerName:     customer.name,
      amount:           amount,
      paymentMethodStr: selectedPayMethod.value,
      note:             paymentNoteCtrl.text.trim().isEmpty
          ? null : paymentNoteCtrl.text.trim(),
    );

    isRecordingPayment.value = false;

    if (ok) {
      paymentAmountCtrl.clear();
      paymentNoteCtrl.clear();
      selectedPayMethod.value = 'cash';
      _loadCustomers();        // refresh cache-based lists
      Get.back();
      Get.snackbar(
        '💰 Collected',
        '₹${amount.toStringAsFixed(0)} from ${customer.name}',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF22C55E),
        colorText: const Color(0xFFFFFFFF),
      );
    } else {
      Get.snackbar('Error', 'Could not record payment.',
          snackPosition: SnackPosition.TOP);
    }
  }

  /// Record payment against a specific bill.
  Future<void> recordPaymentForBill(InvoiceModel bill, double amount) async {
    if (vendorId == null) return;
    isRecordingPayment.value = true;

    final ok = await _billing.recordPayment(
      vendorId:         vendorId!,
      customerId:       bill.customerId,
      customerName:     bill.customerName,
      amount:           amount,
      paymentMethodStr: selectedPayMethod.value,
      billId:           bill.id,
      note:             paymentNoteCtrl.text.trim().isEmpty
          ? null : paymentNoteCtrl.text.trim(),
    );

    isRecordingPayment.value = false;
    if (ok) {
      paymentAmountCtrl.clear();
      paymentNoteCtrl.clear();
      Get.back();
      Get.snackbar(
        '💰 Payment Recorded',
        '₹${amount.toStringAsFixed(0)} for ${bill.customerName}',
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // BILL GENERATION
  // ══════════════════════════════════════════════════════════════════════

  Future<void> generateMonthlyBill(CustomerModel customer) async {
    if (vendorId == null) return;
    isGenerating.value = true;
    final now = DateTime.now();

    final bill = await _billing.generateMonthlyBill(
      vendorId:  vendorId!,
      customer:  customer,
      month:     now.month,
      year:      now.year,
    );

    isGenerating.value = false;

    if (bill != null) {
      Get.snackbar(
        '✅ Bill Generated',
        '₹${bill.totalAmount.toStringAsFixed(0)} for ${customer.name}',
        snackPosition: SnackPosition.TOP,
      );
    } else {
      Get.snackbar(
        'No Deliveries',
        'No new delivered items found for ${customer.name} this month.',
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  Future<void> generateAllMonthlyBills() async {
    if (vendorId == null) return;
    isGenerating.value = true;
    int count = 0;
    final now = DateTime.now();

    for (final customer in allCustomers) {
      final bill = await _billing.generateMonthlyBill(
        vendorId: vendorId!,
        customer: customer,
        month:    now.month,
        year:     now.year,
      );
      if (bill != null) count++;
    }

    isGenerating.value = false;
    Get.snackbar(
      '✅ Bills Generated',
      '$count bills created for ${now.month}/${now.year}',
      snackPosition: SnackPosition.TOP,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // OVERDUE CHECK
  // ══════════════════════════════════════════════════════════════════════

  Future<void> markOverdueBills() async {
    if (vendorId == null) return;
    await _billing.markOverdueBills(vendorId!);
  }

  // ══════════════════════════════════════════════════════════════════════
  // VIEW INVOICE
  // ══════════════════════════════════════════════════════════════════════

  Future<void> viewInvoice(InvoiceModel bill) async {
    try {
      final customer = allCustomers.firstWhereOrNull((c) => c.id == bill.customerId);
      if (customer == null) {
        Get.snackbar('Error', 'Customer not found.');
        return;
      }

      final file = await _pdf.generateInvoicePdf(bill, customer);
      final bytes = await file.readAsBytes();

      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Invoice_${bill.invoiceNumber}',
      );
    } catch (e) {
      AppLogger.e('BillingController: viewInvoice error', e);
      Get.snackbar('Error', 'Could not open invoice.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ══════════════════════════════════════════════════════════════════════

  @override
  void onClose() {
    _pendingSub?.cancel();
    _paidSub?.cancel();
    _todayPaySub?.cancel();
    _customerSub?.cancel();
    paymentAmountCtrl.dispose();
    paymentNoteCtrl.dispose();
    super.onClose();
  }
}
