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
import '../../shared/widgets/content_width.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/l10n/app_language.dart';

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
                    const SizedBox(height: 24),
                    const LanguagePicker(),
                    const SizedBox(height: 24),
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
                          child: Text(
                            context.tr('Forgot your password?'),
                            style: TextStyle(fontSize: 14),
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
                          // Not available yet: shown disabled, not as a
                          // button that does nothing.
                          onPressed: null,
                          icon: const Icon(Icons.login, size: IconSize.s),
                          label: Text(context.tr('Continue with Google')),
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
                              text: context.tr(
                                signUp
                                    ? 'Already have an account? '
                                    : "Don't have an account? ",
                              ),
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
                                    context.tr(signUp ? 'Login' : 'Sign up'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.accentDeep,
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
                          context.tr(
                            'Offline mode: accounts stay on this device.',
                          ),
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
    final sentText = context.tr(
      'If an account exists for that email, a reset link is on its way.',
    );
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(sentText)));
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
      title: Text(context.tr('Reset password')),
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
          child: Text(context.tr('Cancel')),
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
          child: Text(
            context.tr('or'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Shown after the user opens a password-reset email link: sets the new
/// password, then the router sends them on.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      ref.read(passwordRecoveryProvider.notifier).finish();
    } on AuthFailure catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('New password'))),
      body: ContentWidth(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Gap.l),
            children: [
              AppTextField(
                controller: _password,
                hint: 'New password',
                obscureText: true,
                validator: validatePassword,
              ),
              const SizedBox(height: Gap.m),
              AppTextField(
                controller: _confirm,
                hint: 'Repeat new password',
                obscureText: true,
                validator: (v) =>
                    v == _password.text ? null : "Passwords don't match",
              ),
              const SizedBox(height: Gap.l),
              PrimaryButton(
                label: 'Save password',
                loading: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
