import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'account.dart';

/// Real [AccountService] backed by Supabase Auth (combat-v2 §15). Stress-free
/// onboarding: guest is an anonymous Supabase user (real id, progress kept),
/// email is passwordless (magic link / OTP), and Google/Apple are one-tap
/// OAuth. Upgrading a guest keeps the SAME user id, so no progress is lost.
///
/// OAuth and email flows can't finish synchronously (the web redirects away, or
/// the user clicks a link in their inbox), so those return [AuthResult.awaiting]
/// and the real account lands later through [changes].
class SupabaseAccountService implements AccountService {
  final sb.SupabaseClient _client;
  final _controller = StreamController<PlayerAccount?>.broadcast();
  late final StreamSubscription<sb.AuthState> _sub;
  PlayerAccount? _current;

  SupabaseAccountService(this._client) {
    _current = _accountFrom(_client.auth.currentUser);
    _sub = _client.auth.onAuthStateChange.listen((state) {
      _current = _accountFrom(state.session?.user);
      _controller.add(_current);
    });
  }

  @override
  PlayerAccount? get current => _current;

  @override
  Stream<PlayerAccount?> get changes => _controller.stream;

  @override
  Future<AuthResult> continueAsGuest() => _guard(() async {
    await _client.auth.signInAnonymously();
    final account = _accountFrom(_client.auth.currentUser);
    return account != null
        ? AuthResult.success(account)
        : const AuthResult.failure('Could not start a guest session.');
  });

  @override
  Future<AuthResult> signInWithGoogle() => _oauth(sb.OAuthProvider.google);

  @override
  Future<AuthResult> signInWithApple() => _oauth(sb.OAuthProvider.apple);

  Future<AuthResult> _oauth(sb.OAuthProvider provider) => _guard(() async {
    await _client.auth.signInWithOAuth(provider, redirectTo: _redirectTo);
    return AuthResult.awaiting('Continuing with ${_providerLabel(provider)}...');
  });

  @override
  Future<AuthResult> signInWithEmailLink(String email) => _guard(() async {
    if (!_looksLikeEmail(email)) {
      return const AuthResult.failure('Enter a valid email address.');
    }
    await _client.auth.signInWithOtp(email: email, emailRedirectTo: _redirectTo);
    return const AuthResult.awaiting('Check your email for a sign-in link.');
  });

  @override
  Future<AuthResult> linkGuest(AuthMethod method, {String? email}) =>
      _guard(() async {
        final user = _client.auth.currentUser;
        if (user == null || !user.isAnonymous) {
          return const AuthResult.failure('No guest account to upgrade.');
        }
        switch (method) {
          case AuthMethod.email:
            if (email == null || !_looksLikeEmail(email)) {
              return const AuthResult.failure('Enter a valid email address.');
            }
            await _client.auth.updateUser(sb.UserAttributes(email: email));
            return const AuthResult.awaiting(
              'Check your email to confirm and keep your progress.',
            );
          case AuthMethod.google:
            await _client.auth.linkIdentity(
              sb.OAuthProvider.google,
              redirectTo: _redirectTo,
            );
            return const AuthResult.awaiting('Linking your Google account...');
          case AuthMethod.apple:
            await _client.auth.linkIdentity(
              sb.OAuthProvider.apple,
              redirectTo: _redirectTo,
            );
            return const AuthResult.awaiting('Linking your Apple account...');
          case AuthMethod.guest:
            return const AuthResult.failure('Already playing as a guest.');
        }
      });

  @override
  Future<void> signOut() => _client.auth.signOut();

  void dispose() {
    _sub.cancel();
    _controller.close();
  }

  // --- helpers -------------------------------------------------------------

  Future<AuthResult> _guard(Future<AuthResult> Function() run) async {
    try {
      return await run();
    } on sb.AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  PlayerAccount? _accountFrom(sb.User? user) {
    if (user == null) return null;
    final method = _methodFor(user);
    final email = user.email;
    final metaName = user.userMetadata?['display_name'] as String?;
    final name = metaName ??
        (email != null && email.isNotEmpty ? email.split('@').first : null) ??
        (method == AuthMethod.guest ? 'Guest' : 'Player');
    return PlayerAccount(
      id: user.id,
      displayName: name,
      email: email,
      method: method,
    );
  }

  AuthMethod _methodFor(sb.User user) {
    if (user.isAnonymous) return AuthMethod.guest;
    final provider = user.appMetadata['provider'] as String?;
    return switch (provider) {
      'google' => AuthMethod.google,
      'apple' => AuthMethod.apple,
      _ => AuthMethod.email,
    };
  }

  bool _looksLikeEmail(String value) =>
      value.contains('@') && value.contains('.');

  String _providerLabel(sb.OAuthProvider provider) =>
      provider == sb.OAuthProvider.apple ? 'Apple' : 'Google';

  /// Where OAuth / magic-link flows return to. On web that's the current
  /// deployed page; native platforms use their configured deep link (null lets
  /// the SDK use its default).
  String? get _redirectTo =>
      kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null;
}
