import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_strings.dart';

class OtpService {
  // Test/backdoor numbers - fixed OTP, no real SMS sent to these
  static const Set<String> _testPhones = {
    '9756765881',
    '7037473395',
    '9058055350',
  };
  static const String _testOtp = '745680';
  static const String _testSession = 'TEST_SESSION_LOCAL';

  // Send OTP — returns session string, null on failure
  static Future<String?> sendOtp(String phone) async {
    // Bypass for test numbers
    if (_testPhones.contains(phone)) {
      return _testSession;
    }
    try {
      final url = Uri.parse(
        'https://2factor.in/API/V1/${AppStrings.otpApiKey}/SMS/$phone/AUTOGEN',
      );
      final res = await http
          .get(url)
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (data['Status'] == 'Success') {
        return data['Details'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Verify OTP — returns true if correct
  static Future<bool> verifyOtp(String session, String otp) async {
    // Bypass for test session
    if (session == _testSession) {
      return otp == _testOtp;
    }
    try {
      final url = Uri.parse(
        'https://2factor.in/API/V1/${AppStrings.otpApiKey}/SMS/VERIFY/$session/$otp',
      );
      final res = await http
          .get(url)
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return data['Status'] == 'Success';
    } catch (_) {
      return false;
    }
  }
}
