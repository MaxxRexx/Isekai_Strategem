import 'package:flutter/material.dart';

import '../game/account.dart';
import '../game/services.dart';
import '../ui/palette.dart';

/// The stress-free onboarding / account sheet (combat-v2 §15). Guest-first: the
/// biggest, friction-free option is "Play as Guest", then one-tap social, then
/// passwordless email. When already signed in it shows the account and XP with
/// an option to upgrade a guest or sign out. Reads everything through
/// [Services.instance] so it works with the real backend or the local stubs.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.panel,
    builder: (_) => const AccountSheet(),
  );

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _emailController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  bool _showEmailField = false;

  AccountService get _accounts => Services.instance.accountService;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _message = null;
      } else if (result.isPending) {
        _message = result.pending;
        _messageIsError = false;
      } else {
        _message = result.error;
        _messageIsError = true;
      }
    });
    if (result.ok && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StreamBuilder<PlayerAccount?>(
          stream: _accounts.changes,
          initialData: _accounts.current,
          builder: (context, snapshot) {
            final account = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'ACCOUNT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    if (!Services.instance.backendLive)
                      const Text(
                        'offline (local)',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (account == null || account.isGuest)
                  ..._onboarding(account)
                else
                  ..._signedIn(account),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError ? Palette.danger : Palette.good,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _onboarding(PlayerAccount? guest) {
    final upgrading = guest != null && guest.isGuest;
    return [
      Text(
        upgrading
            ? 'Save your progress. Link an account and keep everything you\'ve earned.'
            : 'Jump in now. No sign-up needed, and you can save your progress any time.',
        style: const TextStyle(color: Colors.white60, fontSize: 12.5),
      ),
      const SizedBox(height: 16),
      if (!upgrading)
        _primaryButton(
          icon: Icons.play_arrow,
          label: 'Play as Guest',
          onTap: () => _run(_accounts.continueAsGuest),
        ),
      if (!upgrading) const SizedBox(height: 10),
      _socialButton(
        icon: Icons.g_mobiledata,
        label: upgrading ? 'Link Google' : 'Continue with Google',
        onTap: () => _run(
          upgrading
              ? () => _accounts.linkGuest(AuthMethod.google)
              : _accounts.signInWithGoogle,
        ),
      ),
      const SizedBox(height: 10),
      _socialButton(
        icon: Icons.apple,
        label: upgrading ? 'Link Apple' : 'Continue with Apple',
        onTap: () => _run(
          upgrading
              ? () => _accounts.linkGuest(AuthMethod.apple)
              : _accounts.signInWithApple,
        ),
      ),
      const SizedBox(height: 10),
      if (!_showEmailField)
        _socialButton(
          icon: Icons.mail_outline,
          label: upgrading ? 'Link email' : 'Continue with email',
          onTap: () => setState(() => _showEmailField = true),
        )
      else
        _emailRow(upgrading),
    ];
  }

  Widget _emailRow(bool upgrading) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'you@email.com',
            hintStyle: TextStyle(color: Colors.white30),
            isDense: true,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Palette.accent),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _run(
                () => upgrading
                    ? _accounts.linkGuest(
                        AuthMethod.email,
                        email: _emailController.text.trim(),
                      )
                    : _accounts.signInWithEmailLink(
                        _emailController.text.trim(),
                      ),
              ),
        child: const Text('Send link'),
      ),
    ],
  );

  List<Widget> _signedIn(PlayerAccount account) => [
    Row(
      children: [
        CircleAvatar(
          backgroundColor: Palette.accent.withValues(alpha: 0.2),
          child: Text(
            account.displayName.isNotEmpty
                ? account.displayName[0].toUpperCase()
                : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '${account.method.label}${account.email != null ? ' · ${account.email}' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    FutureBuilder<int>(
      future: Services.instance.xpLedger.currentXp(account.id),
      builder: (context, snap) => Row(
        children: [
          const Icon(Icons.star, color: Palette.gold, size: 16),
          const SizedBox(width: 6),
          Text(
            '${snap.data ?? 0} XP',
            style: const TextStyle(color: Palette.gold, fontSize: 13),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _busy ? null : () => _run(() async {
        await _accounts.signOut();
        return const AuthResult.awaiting('Signed out.');
      }),
      icon: const Icon(Icons.logout, size: 16),
      label: const Text('Sign out'),
    ),
  ];

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => FilledButton.icon(
    onPressed: _busy ? null : onTap,
    icon: Icon(icon),
    label: Text(label),
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      backgroundColor: Palette.accent,
      foregroundColor: Colors.black,
    ),
  );

  Widget _socialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => OutlinedButton.icon(
    onPressed: _busy ? null : onTap,
    icon: Icon(icon, size: 20),
    label: Align(
      alignment: Alignment.centerLeft,
      child: Text(label),
    ),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(46),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
    ),
  );
}
