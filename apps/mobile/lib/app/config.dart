/// Build-time configuration, supplied with `--dart-define-from-file=env/<flavor>.json`.
/// Only public values live here; there are no secrets in the app binary.
class AppConfig {
  const AppConfig._();

  static const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Career Ops');
  static const flavor = String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
  static const authDiscoveryUrl = String.fromEnvironment('AUTH_DISCOVERY_URL');
  static const authClientId = String.fromEnvironment('AUTH_CLIENT_ID');
  static const authApiScope = String.fromEnvironment('AUTH_API_SCOPE');
  static const authRedirectUri = String.fromEnvironment(
    'AUTH_REDIRECT_URI',
    defaultValue: 'com.koushiknavuluri.careerpocket://auth',
  );

  static bool get isAuthConfigured =>
      authDiscoveryUrl.isNotEmpty && authClientId.isNotEmpty && authApiScope.isNotEmpty;

  static List<String> get scopes => ['openid', 'profile', 'offline_access', authApiScope];

  static const aiModelLabel = 'GPT-5 mini on Azure OpenAI';
}
