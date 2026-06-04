// lib/services/local_storage_service.dart
// MODIFIED: added bills, payments, ledger boxes + CRUD methods.

import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../data/models/delivery_area_model.dart';
import '../data/models/invoice_model.dart';
import '../data/models/customer_model.dart';
import '../data/models/delivery_model.dart';
import '../data/models/ledger_entry_model.dart';
import '../data/models/payment_model.dart';
import '../data/models/plan_model.dart';
import '../data/models/subscription_model.dart';
import '../data/models/sync_action_model.dart';
import '../data/models/time_slot_model.dart';
import '../data/models/vendor_model.dart';

class LocalStorageService {
  static late Box<dynamic>          _settings;
  static late Box<VendorModel>      _vendorBox;
  static late Box<CustomerModel>    _customersBox;
  static late Box<DeliveryModel>    _deliveriesBox;
  static late Box<SubscriptionModel> _subscriptionsBox;
  static late Box<SyncActionModel>  _syncQueueBox;
  // NEW ↓
  static late Box<InvoiceModel>     _invoicesBox;
  static late Box<PaymentModel>     _paymentsBox;
  static late Box<LedgerEntryModel> _ledgerBox;
  static late Box<TimeSlotModel>    _timeSlotsBox;
  static late Box<DeliveryAreaModel> _areasBox;
  static late Box<PlanModel>         _plansBox;

  static Future<void> init() async {
    try {
      await _initBoxes();
      AppLogger.i('LocalStorageService initialized');
    } catch (e) {
      AppLogger.e('Hive initialization failed: $e');
      // Handle schema mismatch/corruption in caches
      if (e is TypeError || e.toString().contains('type cast')) {
        AppLogger.w('Schema mismatch detected, clearing caches...');
        try {
          await Hive.deleteBoxFromDisk(AppConstants.boxDeliveries);
          await Hive.deleteBoxFromDisk(AppConstants.boxCustomers);
          await Hive.deleteBoxFromDisk(AppConstants.boxSubscriptions);
          // Retry initialization
          await _initBoxes();
          AppLogger.i('LocalStorageService re-initialized after clearing cache');
        } catch (retryError) {
          AppLogger.e('Retry initialization failed: $retryError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  static Future<void> _initBoxes() async {
    _settings         = await Hive.openBox(AppConstants.boxSettings);
    _vendorBox        = await Hive.openBox<VendorModel>(AppConstants.boxVendor);
    _customersBox     = await Hive.openBox<CustomerModel>(AppConstants.boxCustomers);
    _deliveriesBox    = await Hive.openBox<DeliveryModel>(AppConstants.boxDeliveries);
    _subscriptionsBox = await Hive.openBox<SubscriptionModel>(AppConstants.boxSubscriptions);
    _syncQueueBox     = await Hive.openBox<SyncActionModel>(AppConstants.boxSyncQueue);
    _invoicesBox      = await Hive.openBox<InvoiceModel>(AppConstants.boxBills);
    _paymentsBox      = await Hive.openBox<PaymentModel>(AppConstants.boxPayments);
    _ledgerBox        = await Hive.openBox<LedgerEntryModel>(AppConstants.boxLedger);
    _timeSlotsBox     = await Hive.openBox<TimeSlotModel>(AppConstants.boxTimeSlots);
    _areasBox         = await Hive.openBox<DeliveryAreaModel>(AppConstants.boxAreas);
    _plansBox         = await Hive.openBox<PlanModel>(AppConstants.boxPlans);
  }



  // ── Settings ─────────────────────────────────────────────────────────
  static T? getSetting<T>(String key, {T? defaultValue}) =>
      _settings.get(key, defaultValue: defaultValue);
  static Future<void> saveSetting(String key, dynamic value) =>
      _settings.put(key, value);
  static Future<void> deleteSetting(String key) => _settings.delete(key);
  static bool get isDarkMode => getSetting('dark_mode', defaultValue: false)!;
  static Future<void> setDarkMode(bool value) => saveSetting('dark_mode', value);
  static String? get vendorId => getSetting('vendor_id');
  static Future<void> setVendorId(String id) => saveSetting('vendor_id', id);
  static bool get isLoggedIn => vendorId != null;

  // ── Vendor ────────────────────────────────────────────────────────────
  static VendorModel? getVendor() => _vendorBox.get('current');
  static Future<void> saveVendor(VendorModel v) => _vendorBox.put('current', v);
  static Future<void> clearVendor() => _vendorBox.clear();

  // ── Customers ─────────────────────────────────────────────────────────
  static List<CustomerModel> getCustomers() => _customersBox.values.toList();
  static CustomerModel? getCustomer(String id) => _customersBox.get(id);
  static Future<void> saveCustomer(CustomerModel c) => _customersBox.put(c.id, c);
  static Future<void> saveCustomers(List<CustomerModel> cs) async =>
      _customersBox.putAll({for (final c in cs) c.id: c});
  static Future<void> deleteCustomer(String id) => _customersBox.delete(id);
  static Future<void> clearCustomers() => _customersBox.clear();

  // ── Deliveries ────────────────────────────────────────────────────────
  static List<DeliveryModel> getDeliveries() => _deliveriesBox.values.toList();
  static List<DeliveryModel> getTodayDeliveries() {
    final t = DateTime.now();
    return _deliveriesBox.values.where((d) {
      final s = d.scheduledDate;
      return s.year == t.year && s.month == t.month && s.day == t.day;
    }).toList()..sort((a, b) => a.routeOrder.compareTo(b.routeOrder));
  }
  static Future<void> saveDelivery(DeliveryModel d) => _deliveriesBox.put(d.id, d);
  static Future<void> saveDeliveries(List<DeliveryModel> ds) async =>
      _deliveriesBox.putAll({for (final d in ds) d.id: d});
  static Future<void> clearDeliveries() => _deliveriesBox.clear();

  // ── Subscriptions ─────────────────────────────────────────────────────
  static List<SubscriptionModel> getSubscriptions() => _subscriptionsBox.values.toList();
  static Future<void> saveSubscription(SubscriptionModel s) => _subscriptionsBox.put(s.id, s);
  static Future<void> saveSubscriptions(List<SubscriptionModel> ss) async =>
      _subscriptionsBox.putAll({for (final s in ss) s.id: s});
  static Future<void> clearSubscriptions() => _subscriptionsBox.clear();

  // ── Time Slots ────────────────────────────────────────────────────────
  static List<TimeSlotModel> getTimeSlots() => _timeSlotsBox.values.toList();
  static Future<void> saveTimeSlot(TimeSlotModel s) => _timeSlotsBox.put(s.id, s);
  static Future<void> saveTimeSlots(List<TimeSlotModel> ss) async =>
      _timeSlotsBox.putAll({for (final s in ss) s.id: s});
  static Future<void> clearTimeSlots() => _timeSlotsBox.clear();

  // ── Delivery Areas ────────────────────────────────────────────────────
  static List<DeliveryAreaModel> getAreas() => _areasBox.values.toList();
  static Future<void> saveArea(DeliveryAreaModel a) => _areasBox.put(a.id, a);
  static Future<void> saveAreas(List<DeliveryAreaModel> as) async =>
      _areasBox.putAll({for (final a in as) a.id: a});
  static Future<void> clearAreas() => _areasBox.clear();

  // ── Plans ─────────────────────────────────────────────────────────────
  static List<PlanModel> getPlans() => _plansBox.values.toList();
  static Future<void> savePlan(PlanModel p) => _plansBox.put(p.id, p);
  static Future<void> savePlans(List<PlanModel> ps) async =>
      _plansBox.putAll({for (final p in ps) p.id: p});
  static Future<void> clearPlans() => _plansBox.clear();



  // ── Invoices ──────────────────────────────────────────────────────────
  static List<InvoiceModel> getBills() => _invoicesBox.values.toList();

  static List<InvoiceModel> getBillsForCustomer(String customerId) =>
      _invoicesBox.values.where((b) => b.customerId == customerId).toList()
        ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

  static InvoiceModel? getLatestBillForCustomer(String customerId) {
    final bills = getBillsForCustomer(customerId);
    return bills.isEmpty ? null : bills.first;
  }

  static Future<void> saveBill(InvoiceModel bill) => _invoicesBox.put(bill.id, bill);

  static Future<void> saveBills(List<InvoiceModel> bills) async =>
      _invoicesBox.putAll({for (final b in bills) b.id: b});

  static Future<void> clearBills() => _invoicesBox.clear();

  // ── Payments ──────────────────────────────────────────────────────────
  static List<PaymentModel> getPayments() => _paymentsBox.values.toList();

  static List<PaymentModel> getPaymentsForCustomer(String customerId) =>
      _paymentsBox.values.where((p) => p.customerId == customerId).toList()
        ..sort((a, b) => b.paidAt.compareTo(a.paidAt));

  static Future<void> savePayment(PaymentModel p) => _paymentsBox.put(p.id, p);
  static Future<void> clearPayments() => _paymentsBox.clear();

  // ── Ledger ────────────────────────────────────────────────────────────
  static List<LedgerEntryModel> getLedger() => _ledgerBox.values.toList();

  static List<LedgerEntryModel> getLedgerForCustomer(String customerId) =>
      _ledgerBox.values.where((e) => e.customerId == customerId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Running balance for customer from local cache.
  static double getBalanceForCustomer(String customerId) {
    final entries = getLedgerForCustomer(customerId);
    return entries.isEmpty ? 0 : entries.last.balanceAfter;
  }

  static Future<void> saveLedgerEntry(LedgerEntryModel e) =>
      _ledgerBox.put(e.id, e);
  static Future<void> clearLedger() => _ledgerBox.clear();

  // ── Sync Queue ────────────────────────────────────────────────────────
  static List<SyncActionModel> getSyncQueue() =>
      _syncQueueBox.values.where((a) => !a.isFailed).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  static Future<void> enqueueSyncAction(SyncActionModel a) => _syncQueueBox.put(a.id, a);
  static Future<void> removeSyncAction(String id) => _syncQueueBox.delete(id);
  static Future<void> markSyncActionFailed(String id) async {
    final a = _syncQueueBox.get(id);
    if (a != null) { a.isFailed = true; await a.save(); }
  }
  static int get pendingSyncCount =>
      _syncQueueBox.values.where((a) => !a.isFailed).length;

  // ── Clear all (logout) ────────────────────────────────────────────────
  static Future<void> clearAll() async {
    await Future.wait([
      _settings.clear(), _vendorBox.clear(), _customersBox.clear(),
      _deliveriesBox.clear(), _subscriptionsBox.clear(), _syncQueueBox.clear(),
      _invoicesBox.clear(), _paymentsBox.clear(), _ledgerBox.clear(),
    ]);
    AppLogger.i('LocalStorageService cleared');
  }
}