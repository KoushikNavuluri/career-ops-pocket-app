import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import 'auth_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, {this.email, this.name, this.error, this.busy = false});
  final AuthStatus status;
  final String? email;
  final String? name;
  final String? error;
  final bool busy;

  AuthState copyWith({AuthStatus? status, String? email, String? name, String? error, bool? busy, bool clearError = false}) {
    return AuthState(
      status ?? this.status,
      email: email ?? this.email,
      name: name ?? this.name,
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  AuthTokens? _tokens;
  Future<AuthTokens?>? _refreshing;

  AuthService get _service => ref.read(authServiceProvider);

  @override
  AuthState build() {
    Future.microtask(restore);
    return const AuthState(AuthStatus.unknown);
  }

  Future<void> restore() async {
    if (!AppConfig.isAuthConfigured) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    final tokens = await _refreshOnce();
    if (tokens == null) {
      state = const AuthState(AuthStatus.signedOut);
    } else {
      _setSignedIn(tokens);
    }
  }

  Future<void> signIn({bool createAccount = false}) async {
    if (!AppConfig.isAuthConfigured) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final tokens = await _service.signIn(createAccount: createAccount);
      _setSignedIn(tokens);
    } on AuthCancelled {
      state = const AuthState(AuthStatus.signedOut);
    } on AuthFailure catch (e) {
      state = AuthState(AuthStatus.signedOut, error: e.message);
    } catch (_) {
      state = const AuthState(AuthStatus.signedOut, error: 'Sign-in didn\'t complete. Please try again.');
    }
  }

  Future<void> signOut() async {
    _tokens = null;
    state = const AuthState(AuthStatus.signedOut);
    await _service.signOut();
  }

  /// Called by the API client when the server rejects a refreshed token.
  void sessionExpired() {
    _tokens = null;
    _service.clear();
    state = const AuthState(AuthStatus.signedOut, error: 'Your session has expired. Sign in again.');
  }

  Future<String?> accessToken({bool forceRefresh = false}) async {
    final current = _tokens;
    if (current != null && !forceRefresh && !current.isExpiring) return current.accessToken;
    final refreshed = await _refreshOnce();
    if (refreshed == null) return null;
    _tokens = refreshed;
    return refreshed.accessToken;
  }

  Future<AuthTokens?> _refreshOnce() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _service.refresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  void _setSignedIn(AuthTokens tokens) {
    _tokens = tokens;
    final claims = decodeJwtClaims(tokens.idToken);
    final email = claims['email'] is String ? claims['email'] as String : null;
    final name = claims['name'] is String ? claims['name'] as String : null;
    state = AuthState(AuthStatus.signedIn, email: email, name: name);
  }
}
