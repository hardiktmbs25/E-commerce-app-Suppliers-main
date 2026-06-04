// lib/data/models/subscription_model.dart
//
// CHANGES vs previous version:
//   • frequencyStr now uses DeliveryFrequency enum names (old 'daily' still
//     deserializes correctly via FrequencyConstants.fromStr).
//   • deliverySlots (List<String>) replaces single deliverySlot String so
//     twice-daily / thrice-daily subscriptions can store multiple time slots.
//   • deliverySlot getter preserved for backward-compat reads.
//   • estimatedMonthlyRevenue uses FrequencyConstants.monthlyDeliveries().
//   • copyWith extended to cover deliverySlots.
//   • Hive field indices: 22 = deliverySlots  (new, additive – old boxes
//     without this field will just use the default empty list safely).
//
// HIVE NOTE: deliverySlots is a NEW field (index 22). Old cached objects
// won't have it. The default value [] + getter fallback to deliverySlot
// ensures zero crashes on upgrade.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/service_constants.dart';
part 'subscription_model.g.dart';

// Keep old enum for any remaining usages elsewhere (delivery scheduler etc.)
// New code should use DeliveryFrequency from service_constants.dart.
enum SubscriptionFrequency { daily, alternateDay, weekdays, weekends, weekly, custom }
enum SubscriptionStatus    { active, paused, cancelled, expired }

@HiveType(typeId: AppConstants.tidSubscriptionModel)
class SubscriptionModel extends HiveObject {
  @HiveField(0)  final String id;
  @HiveField(1)  final String vendorId;
  @HiveField(2)  final String customerId;
  @HiveField(3)  final String customerName;
  @HiveField(4)  final String serviceTypeStr;
  @HiveField(5)  final String frequencyStr;
  @HiveField(6)  final String statusStr;
  @HiveField(7)  final double quantity;
  @HiveField(8)  final String unit;
  @HiveField(9)  final double pricePerUnit;
  @HiveField(10) final double pricePerDelivery;
  /// Legacy single-slot field kept for backward compat. Use [deliverySlots].
  @HiveField(11) final String deliverySlot;
  @HiveField(12) final DateTime startDate;
  @HiveField(13) final DateTime? endDate;
  @HiveField(14) final DateTime? pausedUntil;
  @HiveField(15) final DateTime? nextDeliveryDate;
  @HiveField(16, defaultValue: []) final List<int> customDays;
  @HiveField(17, defaultValue: 0) final int completedDeliveries;
  @HiveField(18, defaultValue: 0) final int pendingDeliveries;
  @HiveField(19) final String? notes;
  @HiveField(20) final DateTime createdAt;
  @HiveField(21) final DateTime updatedAt;
  /// NEW: ordered list of delivery time strings e.g. ['07:00 AM', '01:00 PM']
  @HiveField(22, defaultValue: []) final List<String> deliverySlots;
  @HiveField(23, defaultValue: false) final bool vacationMode;
  @HiveField(24, defaultValue: true) final bool autoResume;

  SubscriptionModel({
    required this.id,
    required this.vendorId,
    required this.customerId,
    required this.customerName,
    required this.serviceTypeStr,
    this.frequencyStr = 'onceDaily',
    this.statusStr = 'active',
    required this.quantity,
    this.unit = 'unit',
    required this.pricePerUnit,
    required this.pricePerDelivery,
    this.deliverySlot = '07:00 AM',
    required this.startDate,
    this.endDate,
    this.pausedUntil,
    this.nextDeliveryDate,
    this.customDays = const [],
    this.completedDeliveries = 0,
    this.pendingDeliveries = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deliverySlots = const [],
    this.vacationMode = false,
    this.autoResume = true,
  });

  // ── Computed ────────────────────────────────────────────────────────────

  DeliveryFrequency get frequency => FrequencyConstants.fromStr(frequencyStr);

  SubscriptionStatus get status => SubscriptionStatus.values.firstWhere(
          (e) => e.name == statusStr, orElse: () => SubscriptionStatus.active);

  bool get isActive => status == SubscriptionStatus.active;
  bool get isPaused => status == SubscriptionStatus.paused;

  /// All time slots: falls back to [deliverySlot] for old records.
  List<String> get effectiveSlots =>
      deliverySlots.isNotEmpty ? deliverySlots : [deliverySlot];

  String get frequencyLabel => FrequencyConstants.labelFor(frequency);

  double get estimatedMonthlyRevenue =>
      pricePerDelivery * FrequencyConstants.monthlyDeliveries(frequency);

  bool shouldDeliverOn(DateTime date) {
    // 1. Core status checks: must not be cancelled or expired
    if (status == SubscriptionStatus.cancelled || status == SubscriptionStatus.expired) {
      return false;
    }

    // Normalize dates to midnight to prevent time-skew bugs
    final targetDate = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);

    // 2. Start date boundary check
    if (targetDate.isBefore(start)) {
      return false;
    }

    // 3. End date boundary check
    if (endDate != null) {
      final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
      if (targetDate.isAfter(end)) {
        return false;
      }
    }

    // 4. Pause date checks
    if (status == SubscriptionStatus.paused || vacationMode) {
      if (pausedUntil != null) {
        final resume = DateTime(pausedUntil!.year, pausedUntil!.month, pausedUntil!.day);
        if (targetDate.isBefore(resume)) {
          return false;
        }
      } else {
        // Paused indefinitely without a resume date
        return false;
      }
    }

    // 5. Frequency specific logic
    switch (frequency) {
      case DeliveryFrequency.onceDaily:
      case DeliveryFrequency.twiceDaily:
      case DeliveryFrequency.thriceDaily:
        return true;
      case DeliveryFrequency.alternateDay:
        return targetDate.difference(start).inDays % 2 == 0;
      case DeliveryFrequency.weekdays:
        return targetDate.weekday >= 1 && targetDate.weekday <= 5;
      case DeliveryFrequency.weekends:
        return targetDate.weekday == 6 || targetDate.weekday == 7;
      case DeliveryFrequency.weekly:
        return targetDate.weekday == start.weekday;
      default:
        // Handle custom days if applicable
        if (customDays.isNotEmpty) {
           return customDays.contains(targetDate.weekday);
        }
        return true;
    }
  }

  // ── Firestore ────────────────────────────────────────────────────────────

  factory SubscriptionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawSlots = d['deliverySlots'];
    final List<String> slots = rawSlots != null
        ? List<String>.from(rawSlots)
        : [];
    return SubscriptionModel(
      id:                   doc.id,
      vendorId:             d['vendorId'] ?? '',
      customerId:           d['customerId'] ?? '',
      customerName:         d['customerName'] ?? '',
      serviceTypeStr:       d['serviceType'] ?? 'custom',
      frequencyStr:         d['frequency'] ?? 'onceDaily',
      statusStr:            d['status'] ?? 'active',
      quantity:             (d['quantity'] ?? 1).toDouble(),
      unit:                 d['unit'] ?? 'unit',
      pricePerUnit:         (d['pricePerUnit'] ?? 0).toDouble(),
      pricePerDelivery:     (d['pricePerDelivery'] ?? 0).toDouble(),
      deliverySlot:         d['deliverySlot'] ?? '07:00 AM',
      deliverySlots:        slots,
      startDate:            (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate:              (d['endDate'] as Timestamp?)?.toDate(),
      pausedUntil:          (d['pausedUntil'] as Timestamp?)?.toDate(),
      nextDeliveryDate:     (d['nextDeliveryDate'] as Timestamp?)?.toDate(),
      customDays:           List<int>.from(d['customDays'] ?? []),
      completedDeliveries:  d['completedDeliveries'] ?? 0,
      pendingDeliveries:    d['pendingDeliveries'] ?? 0,
      notes:                d['notes'],
      createdAt:            (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt:            (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      vacationMode:         d['vacationMode'] ?? false,
      autoResume:           d['autoResume'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'vendorId':            vendorId,
    'customerId':          customerId,
    'customerName':        customerName,
    'serviceType':         serviceTypeStr,
    'frequency':           frequencyStr,
    'status':              statusStr,
    'quantity':            quantity,
    'unit':                unit,
    'pricePerUnit':        pricePerUnit,
    'pricePerDelivery':    pricePerDelivery,
    // Keep legacy field in sync with first slot for old readers
    'deliverySlot':        effectiveSlots.isNotEmpty ? effectiveSlots.first : deliverySlot,
    'deliverySlots':       effectiveSlots,
    'startDate':           Timestamp.fromDate(startDate),
    'endDate':             endDate != null ? Timestamp.fromDate(endDate!) : null,
    'pausedUntil':         pausedUntil != null ? Timestamp.fromDate(pausedUntil!) : null,
    'nextDeliveryDate':    nextDeliveryDate != null ? Timestamp.fromDate(nextDeliveryDate!) : null,
    'customDays':          customDays,
    'completedDeliveries': completedDeliveries,
    'pendingDeliveries':   pendingDeliveries,
    'notes':               notes,
    'createdAt':           Timestamp.fromDate(createdAt),
    'updatedAt':           FieldValue.serverTimestamp(),
    'vacationMode':        vacationMode,
    'autoResume':          autoResume,
  };

  SubscriptionModel copyWith({
    String? statusStr,
    DateTime? pausedUntil,
    DateTime? nextDeliveryDate,
    double? quantity,
    double? pricePerUnit,
    double? pricePerDelivery,
    int? completedDeliveries,
    int? pendingDeliveries,
    List<String>? deliverySlots,
    String? frequencyStr,
    bool? vacationMode,
    bool? autoResume,
    String? serviceTypeStr,
    String? notes,
  }) => SubscriptionModel(
    id: id, vendorId: vendorId, customerId: customerId,
    customerName: customerName, 
    serviceTypeStr:     serviceTypeStr ?? this.serviceTypeStr,
    frequencyStr:       frequencyStr ?? this.frequencyStr,
    statusStr:          statusStr ?? this.statusStr,
    quantity:           quantity ?? this.quantity,
    unit: unit,
    pricePerUnit:       pricePerUnit ?? this.pricePerUnit,
    pricePerDelivery:   pricePerDelivery ?? this.pricePerDelivery,
    deliverySlot:       deliverySlot,
    deliverySlots:      deliverySlots ?? this.deliverySlots,
    startDate: startDate, endDate: endDate,
    pausedUntil:        pausedUntil ?? this.pausedUntil,
    nextDeliveryDate:   nextDeliveryDate ?? this.nextDeliveryDate,
    customDays: customDays,
    completedDeliveries: completedDeliveries ?? this.completedDeliveries,
    pendingDeliveries:  pendingDeliveries ?? this.pendingDeliveries,
    notes:              notes ?? this.notes,
    createdAt: createdAt, updatedAt: DateTime.now(),
    vacationMode:       vacationMode ?? this.vacationMode,
    autoResume:         autoResume ?? this.autoResume,
  );
}