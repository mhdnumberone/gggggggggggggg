import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeModeKey = 'theme_mode_v2';
  static const String _primaryColorKey = 'primary_color_v2';
  static const String _useMaterial3Key = 'use_material3_v2';

  // Define the intelligence-style primary color (same as in app.dart)
  static const Color intelligencePrimaryColor = Color(0xFF004D40);

  // Load ThemeMode from SharedPreferences
  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeModeKey) ?? ThemeMode.system.index;
    // Ensure the index is valid before returning
    if (themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      return ThemeMode.values[themeIndex];
    }
    return ThemeMode.system; // Default fallback
  }

  // Save ThemeMode to SharedPreferences
  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  // Load Primary Color value (int) from SharedPreferences
  Future<int?> loadPrimaryColorValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_primaryColorKey);
  }

  // Load Primary Color from SharedPreferences, defaulting to intelligence color
  Future<Color> loadPrimaryColor() async {
    final colorValue = await loadPrimaryColorValue();
    // Use the intelligence color as the default if no color is saved
    return Color(colorValue ?? intelligencePrimaryColor.value);
  }

  // Save Primary Color to SharedPreferences
  Future<void> savePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_primaryColorKey, color.value);
  }

  // Load Material 3 preference from SharedPreferences
  Future<bool> loadUseMaterial3() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useMaterial3Key) ?? true; // Default to true
  }

  // Save Material 3 preference to SharedPreferences
  Future<void> saveUseMaterial3(bool useMaterial3) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useMaterial3Key, useMaterial3);
  }
}

