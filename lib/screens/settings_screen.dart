import 'package:flutter/material.dart';
import '../services/settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ipaCtrl = TextEditingController(text: SettingsController.adminInstapayAddress);
  final _walletCtrl = TextEditingController(text: SettingsController.adminWalletNumber);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات والخيارات'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('المظهر والعملة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: SettingsController.themeModeNotifier,
            builder: (context, mode, _) {
              return SwitchListTile(
                title: const Text('الوضع الليلي (Dark Mode)'),
                value: mode == ThemeMode.dark,
                onChanged: (val) => SettingsController.toggleTheme(val),
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: SettingsController.currencyNotifier,
            builder: (context, cur, _) {
              return ListTile(
                title: const Text('رمز العملة'),
                trailing: DropdownButton<String>(
                  value: cur,
                  items: const [
                    DropdownMenuItem(value: 'ج.م', child: Text('جنيه مصري (ج.م)')),
                    DropdownMenuItem(value: 'ر.س', child: Text('ريال سعودي (ر.س)')),
                    DropdownMenuItem(value: 'د.ك', child: Text('دينار كويتي (د.ك)')),
                    DropdownMenuItem(value: '\$', child: Text('دولار (\$)')),
                  ],
                  onChanged: (val) {
                    if (val != null) SettingsController.updateCurrency(val);
                  },
                ),
              );
            },
          ),
          const Divider(height: 32),
          const Text('بيانات التحصيل الإلكتروني السريع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _ipaCtrl,
            decoration: const InputDecoration(labelText: 'عنوان InstaPay (IPA)', border: OutlineInputBorder()),
            onChanged: (v) => SettingsController.adminInstapayAddress = v.trim(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _walletCtrl,
            decoration: const InputDecoration(labelText: 'رقم المحفظة (فودافون كاش)', border: OutlineInputBorder()),
            onChanged: (v) => SettingsController.adminWalletNumber = v.trim(),
          ),
        ],
      ),
    );
  }
}
