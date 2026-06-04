// lib/modules/customers/detail/customer_detail_controller.dart
import 'dart:async';
import 'package:get/get.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/invoice_model.dart';
import '../../../data/models/delivery_model.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/delivery_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/billing_service.dart';
import '../../../core/utils/logger.dart';
import '../../../routes/app_routes.dart';
import '../../../services/wallet_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/whatsapp_service.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../core/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class CustomerDetailController extends GetxController {
  final BillingRepository  _billingRepo  = Get.find<BillingRepository>();
  final DeliveryRepository _deliveryRepo = Get.find<DeliveryRepository>();
  final CustomerRepository _customerRepo = Get.find<CustomerRepository>();
  final WalletService      _walletService = Get.find<WalletService>();
  final PdfService         _pdfService    = Get.find<PdfService>();
  final WhatsappService    _whatsappService = Get.find<WhatsappService>();

  final Rxn<CustomerModel>    customer  = Rxn<CustomerModel>();
  final RxList<InvoiceModel>  invoices  = <InvoiceModel>[].obs;
  final RxList<DeliveryModel> recentDeliveries = <DeliveryModel>[].obs;
  final RxBool isLoading         = true.obs;
  final RxBool isGeneratingBill  = false.obs;

  StreamSubscription? _invoiceSub;
  String? get vendorId => LocalStorageService.getVendor()?.id;

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments != null && Get.arguments is CustomerModel) {
      customer.value = Get.arguments as CustomerModel;
      _initStreams();
    }
  }

  void _initStreams() {
    if (vendorId == null || customer.value == null) return;

    _invoiceSub = _billingRepo
        .watchCustomerInvoices(vendorId!, customer.value!.id)
        .listen(
          (list) {
        invoices.assignAll(list);
        isLoading.value = false;
      },
      onError: (e) {
        AppLogger.e('CustomerDetail invoices error', e);
        isLoading.value = false;
      },
    );

    // Load recent deliveries
    _loadRecentDeliveries();
  }

  Future<void> _loadRecentDeliveries() async {
    if (vendorId == null || customer.value == null) return;
    final now = DateTime.now();
    final result = await _deliveryRepo.fetchDeliveryHistory(
      vendorId!,
      startDate:  DateTime(now.year, now.month, 1),
      customerId: customer.value!.id,
    );
    result.fold(
          (f) => AppLogger.e('Recent deliveries error', f.message),
          (list) => recentDeliveries.assignAll(list),
    );
  }

  Future<void> generateBill() async {
    if (vendorId == null || customer.value == null) return;
    isGeneratingBill.value = true;
    final now = DateTime.now();
    final invoice = await Get.find<BillingService>().generateMonthlyBill(
      vendorId:  vendorId!,
      customer:  customer.value!,
      month:     now.month,
      year:      now.year,
    );
    if (invoice != null) {
      Get.snackbar('✅ Bill Generated',
          'Invoice ₹${invoice.totalAmount.toStringAsFixed(0)} created.',
          snackPosition: SnackPosition.TOP);
    } else {
      Get.snackbar('No Deliveries', 'No new delivered items found for this month.',
          backgroundColor: Colors.red, colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    }
    isGeneratingBill.value = false;
  }

  void editCustomer() => Get.toNamed(Routes.addCustomer, arguments: customer.value);

  Future<void> shareInvoice(InvoiceModel invoice) async {
    if (customer.value == null) return;
    try {
      final file = await _pdfService.generateInvoicePdf(invoice, customer.value!);
      final message = "Hello ${customer.value!.name}, here is your invoice for ${invoice.monthName} ${invoice.year}. Total: ₹${invoice.totalAmount}";
      await _whatsappService.sendInvoice(customer.value!.phone, message, file);
    } catch (e) {
      Get.snackbar('Error', 'Failed to share invoice: $e');
    }
  }

  Future<void> viewInvoice(InvoiceModel invoice) async {
    if (customer.value == null) return;
    try {
      final file = await _pdfService.generateInvoicePdf(invoice, customer.value!);
      final bytes = await file.readAsBytes();

      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Invoice_${invoice.invoiceNumber}',
      );
    } catch (e) {
      AppLogger.e('CustomerDetailController: viewInvoice error', e);
      Get.snackbar('Error', 'Could not open invoice.');
    }
  }

  Future<void> togglePause() async {
    if (customer.value == null) return;
    final c = customer.value!;
    final isCurrentlyPaused = c.status == CustomerStatus.paused;
    
    if (isCurrentlyPaused) {
      // Resume
      final updated = c.copyWith(
        statusStr: 'active',
        lastResumeDate: DateTime.now(),
      );
      await _customerRepo.updateCustomer(vendorId!, updated);
      customer.value = updated;
      Get.snackbar('Resumed', 'Customer deliveries resumed');
    } else {
      // Pause - show date picker
      final range = await Get.dialog<DateTimeRange>(
        DateRangePickerDialog(
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: DateTimeRange(
            start: DateTime.now(),
            end: DateTime.now().add(const Duration(days: 7)),
          ),
        ),
      );
      
      if (range != null) {
        final updated = c.copyWith(
          statusStr: 'paused',
          pauseStartDate: range.start,
          pauseEndDate: range.end,
        );
        await _customerRepo.updateCustomer(vendorId!, updated);
        customer.value = updated;
        Get.snackbar('Paused', 'Customer deliveries paused until ${range.end.formatted}');
      }
    }
  }

  Future<void> addMoneyToWallet(double amount) async {
    if (customer.value == null) return;
    await _walletService.addBalance(customer.value!, amount, 'Added by vendor');
    // Reload customer to get new balance
    final updated = await _customerRepo.getCustomer(customer.value!.id);
    if (updated != null) customer.value = updated;
    Get.snackbar('Success', '₹$amount added to wallet');
  }

  void goToAddDelivery() =>
      Get.toNamed(Routes.addDelivery, arguments: customer.value);

  int get deliveredThisMonth =>
      recentDeliveries.where((d) => d.isDelivered).length;
  int get missedThisMonth =>
      recentDeliveries.where((d) => d.isMissed).length;

  @override
  void onClose() {
    _invoiceSub?.cancel();
    super.onClose();
  }
}
