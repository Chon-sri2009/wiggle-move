import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/wiggle_logo.dart';
import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/auth_repository.dart';
import '../../shared/env.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/primary_button.dart';

const minPasswordLength = 8;
const maxNameLength = 40; // profiles.display_name check constraint
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) =>
    (v == null || !_emailPattern.hasMatch(v.trim()))
    ? 'Enter a valid email'
    : null;

String? validatePassword(String? v) =>
    (v == null || v.length < minPasswordLength)
    ? 'At least $minPasswordLength characters'
    : null;

String? validateName(String? v) {
  final name = v?.trim() ?? '';
  if (name.isEmpty) return 'Enter your name';
  if (name.length > maxNameLength) return 'At most $maxNameLength characters';
  return null;
}

/// Login / sign-up from the Figma, backed by [authRepositoryProvider].
/// The router redirect moves on once the auth state changes.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.signUp});
  final bool signUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final repo = ref.read(authRepositoryProvider);
    final email = _email.text.trim();
    setState(() => _busy = true);
    try {
      if (widget.signUp) {
        await repo.signUp(
          email: email,
          password: _password.text,
          displayName: _name.text.trim(),
        );
        // With email confirmation on, Supabase creates no session yet.
        if (repo.currentUser == null && mounted) {
          showAppSnackBar(
            context,
            'Check your email to confirm your account, then log in.',
          );
        }
      } else {
        await repo.signIn(email: email, password: _password.text);
      }
    } on AuthFailure catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() => showDialog<void>(
    context: context,
    builder: (_) => _ResetPasswordDialog(initialEmail: _email.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signUp = widget.signUp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: WiggleLogo(size: 32)),
                    const SizedBox(height: 40),
                    if (signUp) ...[
                      AppTextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        hint: 'Name',
                        validator: validateName,
                      ),
                      const SizedBox(height: 12),
                    ],
                    AppTextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      hint: 'Email',
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _password,
                      obscureText: true,
                      hint: 'Password',
                      validator: validatePassword,
                    ),
                    if (!signUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _forgotPassword,
                          child: const Text(
                            'Forgot your password?',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Center(
                      child: PrimaryButton(
                        onPressed: _submit,
                        loading: _busy,
                        label: signUp ? 'Sign up' : 'Login',
                      ),
                    ),
                    if (!signUp) ...[
                      const SizedBox(height: 16),
                      const _OrDivider(),
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: AppColors.primary,
                          ),
                          onPressed: () => _soon(context, 'Google sign-in'),
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          label: const Text('Continue with Google'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: signUp
                                  ? 'Already have an account? '
                                  : "Don't have an account? ",
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: GestureDetector(
                                onTap: () =>
                                    context.go(signUp ? '/login' : '/signup'),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    signUp ? 'Login' : 'Sign up',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (Env.offline)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Offline mode: accounts stay on this device.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _soon(BuildContext context, String what) {
    showAppSnackBar(context, '$what is coming soon.');
  }
}

/// Asks for an email and sends a reset link. The confirmation is the same
/// whether or not an account exists for that email.
class _ResetPasswordDialog extends ConsumerStatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  ConsumerState<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'If an account exists for that email, a reset link is on its way.',
          ),
        ),
      );
    } on AuthFailure catch (e) {
      // Shown in the dialog: a snackbar would appear behind it.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              hint: 'Email',
              validator: validateEmail,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        PrimaryButton(onPressed: _send, loading: _busy, label: 'Send link'),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('or', style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
