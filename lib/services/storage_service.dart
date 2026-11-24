import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/food_database.dart';
import '../models/food_item.dart';

class StorageService {
  static const _kItems = 'fp_items_v1';
  static const _kApiKey = 'fp_gemini_key_v1';
  static const _kNotifyHour = 'fp_notify_hour_v1';
  static const _kNotifyMin = 'fp_notify_min_v1';
  static const _kSavedCount = 'fp_saved_count_v1';
  static const _kSavedMoney = 'fp_saved_money_v1';

  static Future<List<FoodItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kItems);
    if (raw == null || raw.isEmpty) {
      final initial = buildInitialSampleItems();
      await saveItems(initial);
      return initial;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().map(FoodItem.fromJson).toList();
    } catch (_) {
      return buildInitialSampleItems();
    }
  }

  static Future<void> saveItems(List<FoodItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kItems, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<String> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? '';
  }

  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key.trim());
  }

  static Future<(int, int)> loadNotifyTime() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kNotifyHour) ?? 17, prefs.getInt(_kNotifyMin) ?? 0);
  }

  static Future<void> saveNotifyTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNotifyHour, hour);
    await prefs.setInt(_kNotifyMin, minute);
  }

  static Future<(int, int)> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kSavedCount) ?? 0, prefs.getInt(_kSavedMoney) ?? 0);
  }

  static Future<void> saveStats(int count, int money) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSavedCount, count);
    await prefs.setInt(_kSavedMoney, money);
  }
}
