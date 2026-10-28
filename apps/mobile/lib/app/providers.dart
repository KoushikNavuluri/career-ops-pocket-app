import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';
import '../core/util/json.dart';
import 'config.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.read(authControllerProvider.notifier);
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokens: auth.accessToken,
    onUnauthorized: auth.sessionExpired,
  );
});

class Usage {
  const Usage({required this.period, required this.used, required this.limit});
  final String period;
  final int used;
  final int limit;
  double get fraction => limit <= 0 ? 1 : (used / limit).clamp(0, 1).toDouble();
  int get remaining => limit - used < 0 ? 0 : limit - used;
}

class Profile {
  const Profile(this.raw);
  final Map<String, dynamic> raw;
  String? get alias => strOrNull(raw['alias']);
  String? get targetRole => strOrNull(raw['target_role']);
  String? get northStar => strOrNull(raw['north_star']);
  String? get targetMarket => strOrNull(raw['target_market']);
  String? get workModel => strOrNull(raw['work_model']);
  double? get targetBase => numOrNull(raw['target_base']);
  String? get currency => strOrNull(raw['currency']);
  List<String> get includeKeywords => strList(raw['include_keywords']);
  List<String> get excludeKeywords => strList(raw['exclude_keywords']);
  String get workAuthCheck => strOrNull(raw['work_auth_check']) ?? 'Verify per role';
}

class Preferences {
  const Preferences(this.raw);
  final Map<String, dynamic> raw;
  String get theme => strOrNull(raw['theme']) ?? 'system';
  String get resumeTemplate => strOrNull(raw['resume_template']) ?? 'editorial';
  String get exportFormat => strOrNull(raw['export_format']) ?? 'pdf';
}

class Me {
  const Me({required this.email, required this.plan, required this.onboarded, required this.profile, required this.preferences, required this.usage});
  final String? email;
  final String plan;
  final bool onboarded;
  final Profile profile;
  final Preferences preferences;
  final Usage usage;

  factory Me.fromJson(Map<String, dynamic> j) {
    final user = obj(j['user']);
    final usage = obj(j['usage']);
    return Me(
      email: strOrNull(user['email']),
      plan: strOrNull(user['plan']) ?? 'free',
      onboarded: boolOr(j['onboarded'], false),
      profile: Profile(obj(j['profile'])),
      preferences: Preferences(obj(j['preferences'])),
      usage: Usage(period: str(usage['period']), used: intOr(usage['used'], 0), limit: intOr(usage['limit'], 0)),
    );
  }
}

final meProvider = FutureProvider<Me>((ref) async {
  final auth = ref.watch(authControllerProvider.select((s) => s.status));
  if (auth != AuthStatus.signedIn) throw StateError('signed out');
  final data = await ref.read(apiClientProvider).get('/v1/me');
  return Me.fromJson(obj(data));
});

/// Theme follows the saved preference; a local override applies instantly while saving.
final themeOverrideProvider = NotifierProvider<ThemeOverride, ThemeMode?>(ThemeOverride.new);

class ThemeOverride extends Notifier<ThemeMode?> {
  @override
  ThemeMode? build() => null;
  void set(ThemeMode? mode) => state = mode;
}

final themeModeProvider = Provider<ThemeMode>((ref) {
  final override = ref.watch(themeOverrideProvider);
  if (override != null) return override;
  final pref = ref.watch(meProvider).asData?.value.preferences.theme;
  return themeModeFromPreference(pref);
});

ThemeMode themeModeFromPreference(String? pref) {
  switch (pref) {
    case 'light':
      return ThemeMode.light;
    case 'evening':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
