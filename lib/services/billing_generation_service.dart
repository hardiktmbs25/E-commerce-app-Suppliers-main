// lib/services/billing_generation_service.dart
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../data/models/customer_model.dart';
import '../data/models/delivery_model.dart';
import '../data/models/invoice_model.dart';
import '../data/models/ledger_entry_model.dart';
import '../data/models/sync_action_model.dart';
import 'customer_balance_service.dart';
import 'ledger_service.dart';
import 'connectivity_service.dart';
import 'local_storage_service.dart';

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

      // Group deliveries by serviceType (not subscriptionId, since merged
      // deliveries may share a single primarySubId across multiple plans).
      // Each service type gets one line item with correct delivery count and totals.
      final Map<String, List<DeliveryModel>> grouped = {};
      for (final d in allDeliveries) {
        final key = d.serviceTypeStr;
        grouped[key] = [...(grouped[key] ?? []), d];
      }

      // Compile Line Items — one per service type
      final List<InvoiceLineItem> lineItems = grouped.entries.map((entry) {
        final items        = entry.value;
        final regularItems = items.where((d) => !d.isExtraOrder).toList();
        final extraItems   = items.where((d) => d.isExtraOrder).toList();

        final regularSubtotal = regularItems.fold(0.0, (s, d) => s + d.amount);
        final extraCharges    = extraItems.fold(0.0, (s, d) => s + d.amount);
        final subtotal        = regularSubtotal + extraCharges;

        // avgRate = total regular amount / delivery count (handles merged deliveries correctly)
        final avgRate = regularItems.isNotEmpty
            ? regularSubtotal / regularItems.length
            : (extraItems.isNotEmpty ? extraItems.first.amount : 0.0);

        return InvoiceLineItem(
          subscriptionId: items.first.subscriptionId ?? entry.key,
          description: '${entry.key.toUpperCase()} — ${regularItems.length} deliveries'
              '${extraItems.isNotEmpty ? " + ${extraItems.length} extra" : ""}',
          deliveryCount:    regularItems.length,
          pricePerDelivery: avgRate,
          extraCharges:     extraCharges,
          subtotal:         subtotal,
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

      // 2. Add Debit entry to customer Ledger
      await _ledgerService.createEntry(
        vendorId: vendorId,
        customerId: customer.id,
        type: LedgerEntryType.charge, // Debit entry
        amount: totalAmount,
        description: 'Invoice Generated - ${invoice.invoiceNumber}',
        referenceId: invoiceId,
      );

      // 3. Recalculate customer due balance
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