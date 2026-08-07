import 'dart:async';

/// Combat-v2 section 15 (accounts) - CLIENT SCAFFOLD.
///
/// The whole point of this layer is stress-free, broad-audience onboarding:
///   * Guest-first: [AccountService.continueAsGuest] lets anyone play
///     immediately with NO sign-up wall. Progress is real; they can upgrade to
///     a permanent account later via [AccountService.linkGuest] without losing
///     it.
///   * One-tap social sign-in (Google, Apple, ...).
///   * Passwordless email (a magic link / one-time code) - nothing to
///     remember, nothing to leak.
/// The app only ever talks to [AccountService], so adding providers
/// (Microsoft, Facebook, Game Center / Play Games, ...) never touches call
/// sites. The [LocalStubAccountService] here makes it all work today; a real
/// backend (Supabase/Firebase) drops in behind the same interface later.

/// How a player authenticated. Ordered by onboarding friction (guest = none).
enum AuthMethod { guest, google, apple, email }

extension AuthMethodLabel on AuthMethod {
  String get label => switch (this) {
    AuthMethod.guest => 'Guest',
    AuthMethod.google => 'Google',
    AuthMethod.apple => 'Apple',
    AuthMethod.email => 'Email',
  };
}

/// The common sign-in options to surface, in the order that minimises
/// friction: play now as a guest, then one-tap social, then email. Kept as
/// data so the UI and tests share one source of truth (and new providers show
/// up by adding to this list + the service).
const List<AuthMethod> kOnboardingMethods = [
  AuthMethod.guest,
  AuthMethod.google,
  AuthMethod.apple,
  AuthMethod.email,
];

class PlayerAccount {
  final String id;
  final String displayName;
  final String? email;
  final AuthMethod method;

  const PlayerAccount({
    required this.id,
    required this.displayName,
    required this.method,
    this.email,
  });

  bool get isGuest => method == AuthMethod.guest;

  PlayerAccount copyWith({String? displayName, String? email, AuthMethod? method}) =>
      PlayerAccount(
        id: id,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        method: method ?? this.method,
      );
}

class AuthResult {
  final PlayerAccount? account;
  final String? error;

  const AuthResult.success(PlayerAccount this.account) : error = null;
  const AuthResult.failure(String this.error) : account = null;

  bool get ok => account != null;
}

/// The single entry point the app uses for accounts. Implementations must keep
/// [current] and [changes] in sync so the UI can react to sign-in/out.
abstract class AccountService {
  /// The signed-in (or guest) account, or null if nobody is signed in yet.
  PlayerAccount? get current;

  /// Emits on every account change (sign-in, link, sign-out).
  Stream<PlayerAccount?> get changes;

  /// Zero-friction entry: start playing now, decide about an account later.
  Future<AuthResult> continueAsGuest();

  Future<AuthResult> signInWithGoogle();
  Future<AuthResult> signInWithApple();

  /// Passwordless: sends a magic link / one-time code to [email]. In the stub
  /// this succeeds immediately; the real impl completes when the link is used.
  Future<AuthResult> signInWithEmailLink(String email);

  /// Upgrades the current guest into a permanent account under [method],
  /// KEEPING the same player id so no progress is lost. No-op-with-error if
  /// there is no current guest.
  Future<AuthResult> linkGuest(AuthMethod method, {String? email});

  Future<void> signOut();
}

/// In-memory stand-in so onboarding + XP work before any backend exists. It
/// fabricates accounts locally; it does NOT verify anyone. Swap it for a real
/// AccountService (Supabase/Firebase) without changing call sites.
class LocalStubAccountService implements AccountService {
  PlayerAccount? _current;
  int _seq = 0;
  final _controller = StreamController<PlayerAccount?>.broadcast();

  @override
  PlayerAccount? get current => _current;

  @override
  Stream<PlayerAccount?> get changes => _controller.stream;

  void _set(PlayerAccount? account) {
    _current = account;
    _controller.add(account);
  }

  String _newId(String prefix) => '$prefix-${++_seq}';

  @override
  Future<AuthResult> continueAsGuest() async {
    final account = PlayerAccount(
      id: _newId('guest'),
      displayName: 'Guest',
      method: AuthMethod.guest,
    );
    _set(account);
    return AuthResult.success(account);
  }

  @override
  Future<AuthResult> signInWithGoogle() => _signInSocial(AuthMethod.google);

  @override
  Future<AuthResult> signInWithApple() => _signInSocial(AuthMethod.apple);

  Future<AuthResult> _signInSocial(AuthMethod method) async {
    final account = PlayerAccount(
      id: _newId(method.name),
      displayName: '${method.label} Player',
      email: '${method.name}@example.com',
      method: method,
    );
    _set(account);
    return AuthResult.success(account);
  }

  @override
  Future<AuthResult> signInWithEmailLink(String email) async {
    if (!email.contains('@')) {
      return const AuthResult.failure('Enter a valid email address.');
    }
    final account = PlayerAccount(
      id: _newId('email'),
      displayName: email.split('@').first,
      email: email,
      method: AuthMethod.email,
    );
    _set(account);
    return AuthResult.success(account);
  }

  @override
  Future<AuthResult> linkGuest(AuthMethod method, {String? email}) async {
    final guest = _current;
    if (guest == null || !guest.isGuest) {
      return const AuthResult.failure('No guest account to upgrade.');
    }
    // Keep the SAME id so progress carries over.
    final upgraded = guest.copyWith(
      method: method,
      email: email,
      displayName: email?.split('@').first ?? '${method.label} Player',
    );
    _set(upgraded);
    return AuthResult.success(upgraded);
  }

  @override
  Future<void> signOut() async => _set(null);

  void dispose() => _controller.close();
}
