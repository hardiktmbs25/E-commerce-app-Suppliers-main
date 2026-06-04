// lib/data/repositories/billing_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/logger.dart';
import '../models/invoice_model.dart';
import '../models/ledger_entry_model.dart';
import '../models/payment_model.dart';

class BillingRepository {
  final FirebaseFirestore    _db           = FirebaseFirestore.instance;

  // ── Collection helpers ────────────────────────────────────────────────
  String _invoiceCol(String v)  => '${AppConstants.colVendors}/$v/${AppConstants.colInvoices}';
  String _paymentsCol(String v) => '${AppConstants.colVendors}/$v/${AppConstants.colPayments}';
  String _ledgerCol(String v)   => '${AppConstants.colVendors}/$v/${AppConstants.colLedger}';
  String _customersCol(String v)=> '${AppConstants.colVendors}/$v/${AppConstants.colCustomers}';

  // ══════════════════════════════════════════════════════════════════════
  // INVOICES (CRUD & Streams)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> writeInvoice({
    required String vendorId,
    required InvoiceModel invoice,
  }) async {
    await _db.collection(_invoiceCol(vendorId)).doc(invoice.id).set(invoice.toFirestore());
  }

  Future<Result<void>> updateInvoiceStatus({
    required String vendorId,
    required String invoiceId,
    required String statusStr,
  }) async {
    try {
      await _db.collection(_invoiceCol(vendorId)).doc(invoiceId).update({
        'status':    statusStr,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Result.success(null);
    } catch (e) {
      AppLogger.e('BillingRepository: updateInvoiceStatus error', e);
      return Result.failure(FirestoreFailure(e.toString()));
    }
  }

  /// Live stream of all invoices for a customer.
  Stream<List<InvoiceModel>> watchCustomerInvoices(
      String vendorId, String customerId) {
    return _db
        .collection(_invoiceCol(vendorId))
        .where('customerId', isEqualTo: customerId)
        .orderBy('generatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((doc) => InvoiceModel.fromFirestore(doc)).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchCustomerInvoices error', e);
      throw e;
    });
  }

  /// Live stream of all pending/overdue invoices for the vendor.
  Stream<List<InvoiceModel>> watchPendingInvoices(String vendorId) {
    return _db
        .collection(_invoiceCol(vendorId))
        .where('status', whereIn: [
      InvoiceStatus.sent.name,
      InvoiceStatus.partiallyPaid.name,
      InvoiceStatus.overdue.name,
    ])
        .orderBy('dueDate')
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((doc) => InvoiceModel.fromFirestore(doc)).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchPendingInvoices error', e);
      throw e;
    });
  }

  /// Live stream of all paid invoices for the vendor.
  Stream<List<InvoiceModel>> watchPaidInvoices(String vendorId) {
    return _db
        .collection(_invoiceCol(vendorId))
        .where('status', isEqualTo: InvoiceStatus.paid.name)
        .orderBy('generatedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((doc) => InvoiceModel.fromFirestore(doc)).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchPaidInvoices error', e);
      throw e;
    });
  }

  /// Invoices for a specific month — used for monthly summary.
  Stream<List<InvoiceModel>> watchInvoicesByMonth(
      String vendorId, int month, int year) {
    return _db
        .collection(_invoiceCol(vendorId))
        .where('month', isEqualTo: month)
        .where('year',  isEqualTo: year)
        .orderBy('generatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((doc) => InvoiceModel.fromFirestore(doc)).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchInvoicesByMonth error', e);
      throw e;
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // PAYMENTS (CRUD & Streams)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> writePayment({
    required String vendorId,
    required PaymentModel payment,
  }) async {
    await _db
        .collection(_paymentsCol(vendorId))
        .doc(payment.id)
        .set(payment.toFirestore());
  }

  Stream<List<PaymentModel>> watchCustomerPayments(
      String vendorId, String customerId) {
    return _db
        .collection(_paymentsCol(vendorId))
        .where('customerId', isEqualTo: customerId)
        .orderBy('paidAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(PaymentModel.fromFirestore).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchCustomerPayments error', e);
      throw e;
    });
  }

  Stream<List<PaymentModel>> watchTodayPayments(String vendorId) {
    final startOfDay = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0);
    return _db
        .collection(_paymentsCol(vendorId))
        .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('paidAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PaymentModel.fromFirestore).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchTodayPayments error', e);
      throw e;
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // LEDGER (CRUD & Streams)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> writeLedgerEntry({
    required String vendorId,
    required LedgerEntryModel entry,
  }) async {
    await _db
        .collection(_ledgerCol(vendorId))
        .doc(entry.id)
        .set(entry.toFirestore());
  }

  /// Live stream for a customer's ledger — the core running balance view.
  Stream<List<LedgerEntryModel>> watchCustomerLedger(
      String vendorId, String customerId) {
    return _db
        .collection(_ledgerCol(vendorId))
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(LedgerEntryModel.fromFirestore).toList())
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchCustomerLedger error', e);
      throw e;
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // CUSTOMER BALANCE
  // ══════════════════════════════════════════════════════════════════════

  Future<void> updateCustomerPendingAbsolute({
    required String vendorId,
    required String customerId,
    required double pendingAmount,
  }) async {
    await _db.collection(_customersCol(vendorId)).doc(customerId).update({
      'pendingAmount': pendingAmount,
      'paymentStatus': pendingAmount > 0 ? 'pending' : 'paid',
      'updatedAt':     FieldValue.serverTimestamp(),
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // MONTHLY REVENUE STATS (for dashboard)
  // ══════════════════════════════════════════════════════════════════════

  Stream<Map<String, double>> watchMonthlyRevenue(
      String vendorId, int month, int year) {
    return _db
        .collection(_invoiceCol(vendorId))
        .where('month', isEqualTo: month)
        .where('year',  isEqualTo: year)
        .snapshots()
        .map((snap) {
      double total   = 0;
      double paid    = 0;
      double pending = 0;
      for (final doc in snap.docs) {
        final inv = InvoiceModel.fromFirestore(doc);
        total   += inv.totalAmount;
        paid    += inv.paidAmount;
        pending += inv.pendingAmount;
      }
      return {'total': total, 'paid': paid, 'pending': pending};
    })
        .handleError((Object e) {
      AppLogger.e('BillingRepository: watchMonthlyRevenue error', e);
      throw e;
    });
  }
}