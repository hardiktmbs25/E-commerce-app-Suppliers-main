// lib/core/constants/service_constants.dart
//
// Single source of truth for:
//   • service → default unit mapping
//   • service → icon mapping
//   • service → color mapping
//   • delivery frequency options (new: once/twice/thrice daily + alternate + weekly)
//
// Usage:
//   final unit = ServiceConstants.defaultUnit('milk');   // 'litre'
//   final units = ServiceConstants.unitsFor('water');    // ['bottle', 'can', 'litre']

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

abstract class ServiceConstants {
  // ── Supported service types (matches VendorModel.serviceTypeStr) ──────
  static const String milk      = 'milk';
  static const String water     = 'water';
  static const String newspaper = 'newspaper';
  static const String tiffin    = 'tiffin';
  static const String grocery   = 'grocery';
  static const String custom    = 'custom';

  static const List<String> allServices = [
    milk, water, newspaper, tiffin, grocery, custom,
  ];

  // ── Default unit per service ──────────────────────────────────────────
  static String defaultUnit(String service) {
    switch (service) {
      case milk:      return 'litre';
      case water:     return 'bottle';
      case newspaper: return 'piece';
      case tiffin:    return 'meal';
      case grocery:   return 'kg';
      default:        return 'unit';
    }
  }

  // ── Available units per service ───────────────────────────────────────
  static List<String> unitsFor(String service) {
    switch (service) {
      case milk:
        return ['litre', 'ml', 'packet', 'kg'];
      case water:
        return ['bottle', 'can', 'litre', 'jar'];
      case newspaper:
        return ['piece', 'copy', 'bundle'];
      case tiffin:
        return ['meal', 'box', 'packet', 'piece'];
      case grocery:
        return ['kg', 'g', 'litre', 'packet', 'piece', 'box'];
      default:
        return ['unit', 'piece', 'kg', 'litre', 'packet', 'box'];
    }
  }

  // ── Human-readable label ──────────────────────────────────────────────
  static String labelFor(String service) {
    switch (service) {
      case milk:      return 'Milk';
      case water:     return 'Water';
      case newspaper: return 'Newspaper';
      case tiffin:    return 'Tiffin';
      case grocery:   return 'Grocery';
      default:        return 'Custom';
    }
  }

  // ── Emoji ─────────────────────────────────────────────────────────────
  static String emojiFor(String service) {
    switch (service) {
      case milk:      return '🥛';
      case water:     return '💧';
      case newspaper: return '📰';
      case tiffin:    return '🍱';
      case grocery:   return '🛒';
      default:        return '📦';
    }
  }

  // ── Icon ──────────────────────────────────────────────────────────────
  static IconData iconFor(String service) {
    switch (service) {
      case milk:      return Icons.local_drink_rounded;
      case water:     return Icons.water_drop_rounded;
      case newspaper: return Icons.newspaper_rounded;
      case tiffin:    return Icons.lunch_dining_rounded;
      case grocery:   return Icons.shopping_basket_rounded;
      default:        return Icons.category_rounded;
    }
  }

  // ── Color ─────────────────────────────────────────────────────────────
  static Color colorFor(String service) {
    switch (service) {
      case milk:      return AppColors.milk;
      case water:     return AppColors.water;
      case newspaper: return AppColors.newspaper;
      case tiffin:    return AppColors.tiffin;
      case grocery:   return AppColors.success;
      default:        return AppColors.custom;
    }
  }
}

// ── Delivery Frequency ────────────────────────────────────────────────────
//
// NEW extended enum replacing the old SubscriptionFrequency.
// Hive & Firestore store the .name string so old 'daily' records still work.
//
enum DeliveryFrequency {
  onceDaily,      // once per day  (replaces old 'daily')
  twiceDaily,     // twice per day
  thriceDaily,    // three times per day
  alternateDay,   // every other day
  weekdays,       // mon-fri
  weekends,       // sat-sun
  weekly,         // once per week
}

abstract class FrequencyConstants {
  // ── Human-readable label ──────────────────────────────────────────────
  static String labelFor(DeliveryFrequency f) {
    switch (f) {
      case DeliveryFrequency.onceDaily:    return 'Once a Day';
      case DeliveryFrequency.twiceDaily:   return 'Twice a Day';
      case DeliveryFrequency.thriceDaily:  return '3× a Day';
      case DeliveryFrequency.alternateDay: return 'Alternate Days';
      case DeliveryFrequency.weekdays:     return 'Weekdays (Mon-Fri)';
      case DeliveryFrequency.weekends:     return 'Weekends (Sat-Sun)';
      case DeliveryFrequency.weekly:       return 'Weekly';
    }
  }

  // ── Short label for chips ─────────────────────────────────────────────
  static String shortLabel(DeliveryFrequency f) {
    switch (f) {
      case DeliveryFrequency.onceDaily:    return 'Daily';
      case DeliveryFrequency.twiceDaily:   return '2× Daily';
      case DeliveryFrequency.thriceDaily:  return '3× Daily';
      case DeliveryFrequency.alternateDay: return 'Alt. Days';
      case DeliveryFrequency.weekdays:     return 'Weekdays';
      case DeliveryFrequency.weekends:     return 'Weekends';
      case DeliveryFrequency.weekly:       return 'Weekly';
    }
  }

  // ── Number of delivery slots required ─────────────────────────────────
  static int timeSlotsRequired(DeliveryFrequency f) {
    switch (f) {
      case DeliveryFrequency.twiceDaily:  return 2;
      case DeliveryFrequency.thriceDaily: return 3;
      default:                            return 1;
    }
  }

  // ── Estimated monthly deliveries (for revenue calc) ───────────────────
  static double monthlyDeliveries(DeliveryFrequency f) {
    switch (f) {
      case DeliveryFrequency.onceDaily:    return 30;
      case DeliveryFrequency.twiceDaily:   return 60;
      case DeliveryFrequency.thriceDaily:  return 90;
      case DeliveryFrequency.alternateDay: return 15;
      case DeliveryFrequency.weekdays:     return 22;
      case DeliveryFrequency.weekends:     return 8;
      case DeliveryFrequency.weekly:       return 4;
    }
  }

  // ── Serialize to Firestore string ─────────────────────────────────────
  static String toStr(DeliveryFrequency f) => f.name;

  // ── Deserialize from Firestore/Hive string ────────────────────────────
  // Handles legacy 'daily' from old records gracefully.
  static DeliveryFrequency fromStr(String s) {
    switch (s) {
      case 'daily':        return DeliveryFrequency.onceDaily; // legacy compat
      case 'onceDaily':    return DeliveryFrequency.onceDaily;
      case 'twiceDaily':   return DeliveryFrequency.twiceDaily;
      case 'thriceDaily':  return DeliveryFrequency.thriceDaily;
      case 'alternateDay': return DeliveryFrequency.alternateDay;
      case 'weekdays':     return DeliveryFrequency.weekdays;
      case 'weekends':     return DeliveryFrequency.weekends;
      case 'weekly':       return DeliveryFrequency.weekly;
      default:             return DeliveryFrequency.onceDaily;
    }
  }

  static final List<DeliveryFrequency> all = DeliveryFrequency.values;
}