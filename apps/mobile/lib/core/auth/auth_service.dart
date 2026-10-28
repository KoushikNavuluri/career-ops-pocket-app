import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/config.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.expiresAt, this.refreshToken, this.idToken});
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final String? idToken;

  bool get isExpiring => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

class AuthCancelled implements Exception {}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// OIDC Authorization Code + PKCE against Microsoft Entra External ID (email + password).
/// Refresh and ID tokens live in the platform keystore; the access token only in memory.
class AuthService {
  AuthService({FlutterAppAuth? appAuth, FlutterSecureStorage? storage})
      : _appAuth = appAuth ?? FlutterAppAuth(),
        _storage = storage ?? const FlutterSecureStorage();

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  static const _refreshKey = 'auth.refresh_token';
  static const _idKey = 'auth.id_token';

  Future<AuthTokens> signIn({bool createAccount = false}) async {
    try {
      final res = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConfig.authClientId,
          AppConfig.authRedirectUri,
          discoveryUrl: AppConfig.authDiscoveryUrl,
          scopes: AppConfig.scopes,
          promptValues: createAccount ? const ['create'] : null,
        ),
      );
      return _persist(res.accessToken, res.accessTokenExpirationDateTime, res.refreshToken, res.idToken);
    } on PlatformException catch (e) {
      if (_isCancel(e)) throw AuthCancelled();
      throw AuthFailure('Sign-in didn\'t complete. Please try again.');
    }
  }

  /// Uses the stored refresh token. Returns null when there is no usable session.
  Future<AuthTokens?> refresh() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final res = await _appAuth.token(
        TokenRequest(
          AppConfig.authClientId,
          AppConfig.authRedirectUri,
          discoveryUrl: AppConfig.authDiscoveryUrl,
          refreshToken: refreshToken,
          scopes: AppConfig.scopes,
        ),
      );
      return _persist(res.accessToken, res.accessTokenExpirationDateTime, res.refreshToken ?? refreshToken, res.idToken);
    } on PlatformException {
      await clear();
      return null;
    }
  }

  Future<void> signOut() async {
    final idToken = await _storage.read(key: _idKey);
    await clear();
    if (idToken == null) return;
    try {
      await _appAuth.endSession(
        EndSessionRequest(
          idTokenHint: idToken,
          postLogoutRedirectUrl: AppConfig.authRedirectUri,
          discoveryUrl: AppConfig.authDiscoveryUrl,
        ),
      );
    } on PlatformException {
      // Local sign-out already happened; the browser session will expire on its own.
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _idKey);
  }

  Future<String?> storedIdToken() => _storage.read(key: _idKey);

  Future<AuthTokens> _persist(String? access, DateTime? expires, String? refresh, String? id) async {
    if (access == null || access.isEmpty) throw AuthFailure('Sign-in returned no access token.');
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
    if (id != null) await _storage.write(key: _idKey, value: id);
    return AuthTokens(
      accessToken: access,
      expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 30)),
      refreshToken: refresh,
      idToken: id,
    );
  }

  bool _isCancel(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''}'.toLowerCase();
    return text.contains('cancel');
  }
}

/// Reads display claims from an ID token without verifying it (display only).
Map<String, dynamic> decodeJwtClaims(String? token) {
  if (token == null) return const {};
  final parts = token.split('.');
  if (parts.length != 3) return const {};
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final v = jsonDecode(payload);
    return v is Map ? v.cast<String, dynamic>() : const {};
  } catch (_) {
    return const {};
  }
}
