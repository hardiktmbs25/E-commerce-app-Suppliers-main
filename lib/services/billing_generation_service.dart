// lib/services/billing_generation_service.dart

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:e_commerce_suppliers/core/constants/app_constants.dart';
import 'package:e_commerce_suppliers/core/utils/logger.dart';
import 'package:e_commerce_suppliers/data/models/customer_model.dart';
import 'package:e_commerce_suppliers/data/models/delivery_model.dart';
import 'package:e_commerce_suppliers/data/models/invoice_model.dart';
import 'package:e_commerce_suppliers/data/models/ledger_entry_model.dart';
import 'package:e_commerce_suppliers/data/models/sync_action_model.dart';
import 'package:e_commerce_suppliers/services/customer_balance_service.dart';
import 'package:e_commerce_suppliers/services/ledger_service.dart';
import 'package:e_commerce_suppliers/services/connectivity_service.dart';
import 'package:e_commerce_suppliers/services/local_storage_service.dart';

class BillingGenerationService extends GetxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();
  final LedgerService _ledgerService = Get.find<LedgerService>();
  final CustomerBalanceService _balanceService = Get.find<CustomerBalanceService>();

  String _invoiceCol(String vendorId) =>
      '${AppConstants.colVendors}/$vendorId/${AppConstants.colInvoices}';

  String _deliveriesCol(String vendorId) =>
      '${AppConstants.colVendors}/$vendorId/${AppConstants.colDeliveries}';

  /// Generates a monthly invoice for a specific customer.
  /// IDEMPOTENT: returns existing invoice if already generated for same month/year.
  /// Reconciles delivered items, links their IDs, creates ledger entry,
  /// and updates the customer due balance.
  Future<InvoiceModel?> generateInvoiceForCustomer({
    required String vendorId,
    required CustomerModel customer,
    required int month,
    required int year,
    double discount = 0.0,
  }) async {
    try {
      // IDEMPOTENCY CHECK: return existing invoice for this month/year
      final existingInvoice = LocalStorageService.getBillsForCustomer(customer.id)
          .where((inv) => inv.month == month && inv.year == year)
          .firstOrNull;
      if (existingInvoice != null) {
        AppLogger.w('BillingGenerationService: Invoice already exists for ${customer.name} $month/$year (${existingInvoice.id})');
        return existingInvoice;
      }
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

      // 1. Query delivered unbilled items in calendar range
      final allDeliveries = LocalStorageService.getDeliveries()
          .where((d) =>
      d.vendorId == vendorId &&
          d.customerId == customer.id &&
          d.status == DeliveryStatus.delivered &&
          d.billGenerated == false &&
          !d.scheduledDate.isBefore(startDate) &&
          !d.scheduledDate.isAfter(endDate))
          .toList();

      if (allDeliveries.isEmpty) {
        AppLogger.w('BillingGenerationService: No unbilled deliveries for ${customer.name} in $month/$year');
        return null;
      }

      // Group deliveries by service type instead of subscription ID to aggregate multiple subscriptions
      final Map<String, List<DeliveryModel>> grouped = {};
      for (final d in allDeliveries) {
        final key = d.serviceTypeStr;
        grouped[key] = [...(grouped[key] ?? []), d];
      }

      // Compile Line Items
      final List<InvoiceLineItem> lineItems = grouped.entries.map((entry) {
        final items = entry.value;
        final regularItems = items.where((d) => !d.isExtraOrder).toList();
        final extraItems = items.where((d) => d.isExtraOrder).toList();

        // Total amount for this service type in the billing period
        final totalServiceAmount = items.fold(0.0, (totalVal, d) => totalVal + d.amount);
        
        return InvoiceLineItem(
          subscriptionId: regularItems.isNotEmpty ? regularItems.first.subscriptionId ?? 'mixed' : 'extra',
          description: '${entry.key.toUpperCase()} — ${items.length} total deliveries'
              '${extraItems.isNotEmpty ? " (incl. ${extraItems.length} extra)" : ""}',
          deliveryCount: items.length,
          pricePerDelivery: items.isNotEmpty ? totalServiceAmount / items.length : 0,
          extraCharges: extraItems.fold(0.0, (totalVal, d) => totalVal + d.amount),
          subtotal: totalServiceAmount,
        );
      }).toList();

      final subtotal = lineItems.fold(0.0, (s, l) => s + l.subtotal);
      final totalAmount = (subtotal - discount).clamp(0.0, double.infinity);

      final invoiceId = const Uuid().v4();
      final now = DateTime.now();
      final dueDate = DateTime(year, month + 1, AppConstants.billDueDays);

      final invoice = InvoiceModel(
        id: invoiceId,
        vendorId: vendorId,
        customerId: customer.id,
        customerName: customer.name,
        customerPhone: customer.phone,
        customerAddress: customer.address,
        month: month,
        year: year,
        statusStr: InvoiceStatus.sent.name,
        lineItems: lineItems,
        subtotal: subtotal,
        totalDiscount: discount,
        extraCharges: 0.0,
        totalAmount: totalAmount,
        paidAmount: 0.0,
        pendingAmount: totalAmount,
        generatedAt: now,
        dueDate: dueDate,
        deliveryIds: allDeliveries.map((d) => d.id).toList(),
      );

      // Save locally
      await LocalStorageService.saveBill(invoice);

      // Reconcile and link individual deliveries
      for (final d in allDeliveries) {
        await LocalStorageService.saveDelivery(d.copyWith(
          billGenerated: true,
          invoiceId: invoiceId,
        ));
      }

      // Sync to Firestore
      if (_connectivity.isOnline.value) {
        final batch = _db.batch();
        batch.set(
          _db.collection(_invoiceCol(vendorId)).doc(invoiceId),
          invoice.toFirestore(),
        );

        for (final d in allDeliveries) {
          batch.update(
            _db.collection(_deliveriesCol(vendorId)).doc(d.id),
            {
              'billGenerated': true,
              'invoiceId': invoiceId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        await batch.commit();
      } else {
        // Enqueue offline action queue
        await _enqueueInvoiceSync(vendorId, invoice, allDeliveries);
      }

      // NOTE: Ledger entry creation for the whole invoice is removed here
      // because individual deliveries now create ledger entries instantly
      // upon completion (DeliveryRepository.updateDeliveryStatus).
      // Generating a ledger entry here would result in double-charging.

      // However, if there was a discount applied at invoice generation, 
      // we must record it as a credit in the ledger.
      if (discount > 0) {
        await _ledgerService.createEntry(
          vendorId: vendorId,
          customerId: customer.id,
          type: LedgerEntryType.discount,
          amount: -discount,
          description: 'Invoice Discount - ${invoice.invoiceNumber}',
          referenceId: invoiceId,
        );
      }

      // 3. Recalculate customer due balance strictly
      await _balanceService.recalculateCustomerBalance(
        vendorId: vendorId,
        customerId: customer.id,
      );

      AppLogger.i('Invoice generated successfully: $invoiceId for ${customer.name} totaling ₹$totalAmount');
      return invoice;
    } catch (e, s) {
      AppLogger.e('BillingGenerationService: generateInvoiceForCustomer error', e, s);
      return null;
    }
  }

  Future<void> _enqueueInvoiceSync(String vendorId, InvoiceModel invoice, List<DeliveryModel> deliveries) async {
    // Set operation for Invoice
    await LocalStorageService.enqueueSyncAction(SyncActionModel(
      id: const Uuid().v4(),
      actionTypeStr: SyncActionType.createBill.name,
      collection: _invoiceCol(vendorId),
      documentId: invoice.id,
      payload: invoice.toFirestore(),
      createdAt: DateTime.now(),
    ));

    // Update operation for Deliveries
    for (final d in deliveries) {
      await LocalStorageService.enqueueSyncAction(SyncActionModel(
        id: const Uuid().v4(),
        actionTypeStr: SyncActionType.markDelivery.name,
        collection: _deliveriesCol(vendorId),
        documentId: d.id,
        payload: {
          'billGenerated': true,
          'invoiceId': invoice.id,
        },
        createdAt: DateTime.now(),
      ));
    }
  }
}
