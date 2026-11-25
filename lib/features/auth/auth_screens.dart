import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/wiggle_logo.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/primary_button.dart';
import '../leaderboard/leaderboard_store.dart';

/// Login / sign-up UI from the Figma. Accounts are not connected yet
/// (Supabase is on the roadmap): submitting only stores a display name on
/// the device. Nothing is sent anywhere and the password is discarded.
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

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    final name = widget.signUp ? _name.text.trim() : email.split('@').first;
    // Router redirect moves on to personalization / home once a name is set.
    await ref.read(playerNameProvider.notifier).set(name);
  }

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
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    AppTextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      hint: 'Email',
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _password,
                      obscureText: true,
                      hint: 'Password',
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
                    if (!signUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _soon(context, 'Password reset'),
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
                    if (kDebugMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Dev build: accounts are not connected yet.',
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
