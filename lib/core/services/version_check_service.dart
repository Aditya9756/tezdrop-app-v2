import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/app_strings.dart';

/// Since this app isn't on the Play Store, Android has no built-in way to
/// auto-update it. This does the next best thing: on every launch, check a
/// small Firebase node for the latest version, and if the installed app is
/// older, prompt the user to download the new APK (one tap, not silent —
/// Android doesn't allow silent installs for sideloaded apps).
class VersionCheckService {
  static Future<Map<String, String>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final res = await http
          .get(Uri.parse('${AppStrings.firebaseUrl}/app_config/customer.json'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200 || res.body == 'null') return null;

      final data = jsonDecode(res.body);
      final latestVersion = data['latestVersion']?.toString();
      final downloadUrl = data['downloadUrl']?.toString();

      if (latestVersion == null || downloadUrl == null) return null;
      if (latestVersion == currentVersion) return null;

      return {'latestVersion': latestVersion, 'downloadUrl': downloadUrl};
    } catch (_) {
      return null; // fail silently — an update check should never block the app
    }
  }
}
