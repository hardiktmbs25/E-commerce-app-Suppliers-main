// lib/data/models/plan_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_constants.dart';

part 'plan_model.g.dart';

/// A vendor-defined plan template.
/// Firestore path: vendors/{vendorId}/plans/{planId}
///
/// Changes vs original
/// ───────────────────
/// • [deliverySlotIds]  — list of TimeSlotModel IDs; length drives
///   once / twice / thrice-daily delivery.
/// • [frequencyStr]     — new values: 'twice_daily', 'thrice_daily',
///   'alternate' (replaces old 'alternateDay').
/// • [pricePerDelivery] — computed getter, never stored as a denormalised
///   field that can go stale.
/// • Full null-safe Firestore parsing via [_safe*] helpers.
@HiveType(typeId: AppConstants.tidPlanModel)
class PlanModel extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) final String vendorId;

  /// e.g. "Silver Milk Plan"
  @HiveField(2) final String name;

  /// One of kServiceTypes: milk | water | newspaper | tiffin | grocery | custom
  @HiveField(3) final String serviceType;

  /// One of kFrequencies: daily | twice_daily | thrice_daily |
  ///   alternate | weekdays | weekends | weekly
  @HiveField(4) final String frequencyStr;

  /// Quantity per single delivery slot (e.g. 1.5 litres).
  @HiveField(5) final double quantity;

  /// Unit for [quantity] — e.g. 'litre', 'can', 'piece'.
  @HiveField(6) final String unit;

  /// Price charged per unit.
  @HiveField(7) final double pricePerUnit;

  /// Computed: quantity × pricePerUnit (cost of one delivery slot).
  double get pricePerDelivery => quantity * pricePerUnit;

  /// TimeSlotModel document IDs for delivery windows.
  ///   1 ID  → once daily
  ///   2 IDs → twice daily
  ///   3 IDs → thrice daily
  @HiveField(8) final List<String> deliverySlotIds;

  /// DeliveryAreaModel document IDs where this plan is available.
  /// If empty, it means "All Areas" or default.
  @HiveField(9) final List<String> deliveryAreaIds;

  @HiveField(10) final String description;
  @HiveField(11) final bool isActive;
  @HiveField(12) final DateTime createdAt;
  @HiveField(13) final DateTime updatedAt;

  PlanModel({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.serviceType,
    this.frequencyStr = 'daily',
    required this.quantity,
    this.unit = 'piece',
    required this.pricePerUnit,
    this.deliverySlotIds = const [],
    this.deliveryAreaIds = const [],
    this.description = '',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });


  // ── Firestore ────────────────────────────────────────────────────────────

  factory PlanModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PlanModel(
      id:              doc.id,
      vendorId:        _safeStr(d['vendorId']),
      name:            _safeStr(d['name']),
      serviceType:     _safeStr(d['serviceType'], fallback: 'custom'),
      // legacy 'alternateDay' → 'alternate'
      frequencyStr:    _normaliseFreq(_safeStr(d['frequency'], fallback: 'daily')),
      quantity:        _safeDouble(d['quantity'], fallback: 1.0),
      unit:            _safeStr(d['unit'], fallback: 'piece'),
      pricePerUnit:    _safeDouble(d['pricePerUnit']),
      deliverySlotIds: _safeStrList(d['deliverySlotIds']),
      deliveryAreaIds: _safeStrList(d['deliveryAreaIds']),
      description:     _safeStr(d['description']),
      isActive:        d['isActive'] as bool? ?? true,
      createdAt:       (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt:       (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'vendorId':        vendorId,
    'name':            name,
    'serviceType':     serviceType,
    'frequency':       frequencyStr,
    'quantity':        quantity,
    'unit':            unit,
    'pricePerUnit':    pricePerUnit,
    'pricePerDelivery': pricePerDelivery, // kept for lightweight display queries
    'deliverySlotIds': deliverySlotIds,
    'deliveryAreaIds': deliveryAreaIds,
    'description':     description,
    'isActive':        isActive,
    'createdAt':       Timestamp.fromDate(createdAt),
    'updatedAt':       FieldValue.serverTimestamp(),
  };

  PlanModel copyWith({
    String? name,
    String? serviceType,
    String? frequencyStr,
    double? quantity,
    String? unit,
    double? pricePerUnit,
    List<String>? deliverySlotIds,
    List<String>? deliveryAreaIds,
    String? description,
    bool? isActive,
  }) =>
      PlanModel(
        id:              id,
        vendorId:        vendorId,
        name:            name           ?? this.name,
        serviceType:     serviceType    ?? this.serviceType,
        frequencyStr:    frequencyStr   ?? this.frequencyStr,
        quantity:        quantity       ?? this.quantity,
        unit:            unit           ?? this.unit,
        pricePerUnit:    pricePerUnit   ?? this.pricePerUnit,
        deliverySlotIds: deliverySlotIds ?? this.deliverySlotIds,
        deliveryAreaIds: deliveryAreaIds ?? this.deliveryAreaIds,
        description:     description    ?? this.description,
        isActive:        isActive       ?? this.isActive,
        createdAt:       createdAt,
        updatedAt:       DateTime.now(),
      );

  // ── Private parse helpers ────────────────────────────────────────────────

  static String _safeStr(dynamic v, {String fallback = ''}) =>
      v is String ? v : fallback;

  static double _safeDouble(dynamic v, {double fallback = 0.0}) {
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static List<String> _safeStrList(dynamic v) {
    if (v is List) return v.whereType<String>().toList();
    return [];
  }

  /// Migrate old frequency key spellings.
  static String _normaliseFreq(String f) {
    // Keys must match FrequencyConstants.fromStr expectations
    switch (f) {
      case 'daily':        return 'onceDaily';    // legacy compat
      case 'alternate':    return 'alternateDay'; // legacy compat
      case 'twice_daily':  return 'twiceDaily';   // legacy compat
      case 'thrice_daily': return 'thriceDaily';  // legacy compat
      case 'custom':       return 'onceDaily';    // legacy fallback
      default:             return f;              // 'onceDaily', 'weekly', etc. pass through
    }
  }
}