// lib/core/constants/plan_constants.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// Single source of truth for every Plan-related enum / label / mapping.
//
// Rules:
//  • No Flutter/Material imports — safe to use in model & repo layers.
//  • UI helpers (icons, colours) live in plan_ui_helpers.dart.
//  • Any new service type, unit, or frequency is added HERE only.
// ─────────────────────────────────────────────────────────────────────────────

// ── Service types ─────────────────────────────────────────────────────────────

/// Keys stored in Firestore `serviceType` field.
/// Only vendor-relevant delivery services are permitted.
const List<String> kServiceTypes = [
  'milk',
  'water',
  'newspaper',
  'tiffin',
  'grocery',
  'custom',
];

/// Human-readable label per service key.
const Map<String, String> kServiceLabels = {
  'milk':      'Milk',
  'water':     'Water / Cans',
  'newspaper': 'Newspaper',
  'tiffin':    'Tiffin / Food',
  'grocery':   'Grocery',
  'custom':    'Other',
};

// ── Units ─────────────────────────────────────────────────────────────────────

/// Valid units for each service type.
/// Changing service type in the form rebuilds the unit dropdown from this map.
const Map<String, List<String>> kUnitsForService = {
  'milk':      ['litre', 'ml', 'packet', 'bottle'],
  'water':     ['can', 'bottle', 'litre'],
  'newspaper': ['piece', 'copy'],
  'tiffin':    ['box', 'meal', 'piece'],
  'grocery':   ['kg', 'g', 'packet', 'piece'],
  'custom':    ['piece', 'kg', 'litre', 'packet', 'box', 'bottle', 'can', 'copy'],
};

/// Unit pre-selected when a service type is first chosen.
const Map<String, String> kDefaultUnitForService = {
  'milk':      'litre',
  'water':     'can',
  'newspaper': 'piece',
  'tiffin':    'box',
  'grocery':   'kg',
  'custom':    'piece',
};

/// Display labels shown inside the unit dropdown.
const Map<String, String> kUnitLabels = {
  'litre':  'Litre',
  'ml':     'Millilitre (ml)',
  'packet': 'Packet',
  'bottle': 'Bottle',
  'can':    'Can',
  'piece':  'Piece',
  'copy':   'Copy',
  'box':    'Box',
  'meal':   'Meal',
  'kg':     'Kilogram (kg)',
  'g':      'Gram (g)',
};

// ── Frequencies ───────────────────────────────────────────────────────────────

/// Keys stored in Firestore `frequency` field.
const List<String> kFrequencies = [
  'onceDaily',
  'twiceDaily',
  'thriceDaily',
  'alternateDay',
  'weekdays',
  'weekends',
  'weekly',
];

/// Human-readable frequency labels.
const Map<String, String> kFrequencyLabels = {
  'onceDaily':    'Every Day',
  'twiceDaily':   'Twice a Day',
  'thriceDaily':  'Thrice a Day',
  'alternateDay': 'Alternate Days',
  'weekdays':     'Weekdays (Mon – Fri)',
  'weekends':     'Weekends (Sat & Sun)',
  'weekly':       'Once a Week',
};

/// How many time-slot IDs the plan must carry for each frequency.
const Map<String, int> kRequiredSlotsForFrequency = {
  'onceDaily':    1,
  'twiceDaily':   2,
  'thriceDaily':  3,
  'alternateDay': 1,
  'weekdays':     1,
  'weekends':     1,
  'weekly':       1,
};

// ── Convenience helpers ───────────────────────────────────────────────────────

String serviceLabel(String key) => kServiceLabels[key] ?? key;
String unitLabel(String key)    => kUnitLabels[key] ?? key;
String frequencyLabel(String key) => kFrequencyLabels[key] ?? key;

String defaultUnitForService(String serviceType) =>
    kDefaultUnitForService[serviceType] ?? 'piece';

List<String> unitsForService(String serviceType) =>
    kUnitsForService[serviceType] ?? kUnitsForService['custom']!;

int requiredSlotsForFrequency(String frequency) =>
    kRequiredSlotsForFrequency[frequency] ?? 1;