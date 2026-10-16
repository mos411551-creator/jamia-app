import 'package:flutter/material.dart';

class SettingsController {
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);
  static final ValueNotifier<String> currencyNotifier = ValueNotifier('ج.م');

  static String adminInstapayAddress = 'admin@instapay';
  static String adminWalletNumber = '01000000000';

  static void toggleTheme(bool isDark) {
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  static void updateCurrency(String newCurrency) {
    currencyNotifier.value = newCurrency;
  }
}
