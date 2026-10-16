import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> authenticate() async {
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();

    if (!canCheck && !isSupported) return true;

    try {
      return await _auth.authenticate(
        localizedReason: 'يرجى تأكيد هويتك للوصول إلى الحسابات المالية',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
