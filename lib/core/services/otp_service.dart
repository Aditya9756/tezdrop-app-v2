import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_strings.dart';

class OtpService {
  // Test/backdoor number - fixed OTP, no real SMS sent
  static const String _testPhone = '9756765881';
  static const String _testOtp = '745680';
  static const String _testSession = 'TEST_SESSION_LOCAL';

  // Send OTP — returns session string, null on failure
  static Future<String?> sendOtp(String phone) async {
    // Bypass for test number
    if (phone == _testPhone) {
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
