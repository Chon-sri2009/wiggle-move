import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/auth_repository.dart';
import '../../shared/backend/profile.dart';
import '../../shared/backend/profile_providers.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/primary_button.dart';
import 'profile_options.dart';
import 'profile_store.dart';
import '../../shared/l10n/app_language.dart';

/// Edit name, avatar, goals, styles and level; sign out; delete the account.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;

  /// What is stored now; the edits below are compared against it.
  late Profile _saved;
  late String _savedName;

  late Set<String> _goals;
  late Set<String> _styles;
  String? _level;
  String? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _saved = ref.read(profileProvider).value ?? const Profile();
    _savedName = ref.read(authUserProvider)?.displayName ?? '';
    _name = TextEditingController(text: _savedName)
      ..addListener(() => setState(() {}));
    _goals = {..._saved.goals};
    _styles = {..._saved.styles};
    _level = _saved.level;
    _avatar = _saved.avatar;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Profile get _edited => Profile(
    goals: _ordered(goalOptions, _goals),
    styles: _ordered(styleOptions, _styles),
    level: _level,
    avatar: _avatar,
    onboarded: true,
  );

  /// Selections in the order the options are listed, so equality is stable.
  static List<String> _ordered(List<ProfileOption> options, Set<String> sel) =>
      [
        for (final o in options)
          if (sel.contains(o.label)) o.label,
      ];

  bool get _profileChanged {
    final e = _edited, s = _saved;
    return !(listEquals(e.goals, _ordered(goalOptions, {...s.goals})) &&
        listEquals(e.styles, _ordered(styleOptions, {...s.styles})) &&
        e.level == s.level &&
        e.avatar == s.avatar);
  }

  bool get _nameChanged => _name.text.trim() != _savedName;

  bool get _canSave =>
      !_busy &&
      (_profileChanged || _nameChanged) &&
      _goals.isNotEmpty &&
      _styles.isNotEmpty &&
      _level != null;

  Future<void> _save() async {
    if (!_canSave || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final savedText = context.tr('Profile saved');
    try {
      if (_profileChanged) {
        final next = _edited;
        await ref.read(profileProvider.notifier).save(next);
        _saved = next;
      }
      if (_nameChanged) {
        final name = _name.text.trim();
        // Auth metadata first: if the profile row (what the leaderboard
        // shows) then fails, nothing public changed and a retry is safe.
        await ref.read(authRepositoryProvider).updateDisplayName(name);
        await ref.read(profileRepositoryProvider).saveDisplayName(name);
        _savedName = name;
      }
      messenger.showSnackBar(SnackBar(content: Text(savedText)));
    } on RepositoryFailure catch (e) {
      _showError(e.message);
    } on AuthFailure catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (mounted) showAppSnackBar(context, message, isError: true);
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (e) {
      _showError(e.message);
    }
  }

  void _toggle(Set<String> set, String value) =>
      setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(authUserProvider)?.email ?? '';
    if (!ref.watch(profileProvider).hasValue) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Profile'))),
        body: const LoadingView(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Profile'))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.field,
                  child: Text(
                    _avatar ?? _initial(_name.text),
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in avatarChoices)
                    Semantics(
                      button: true,
                      selected: _avatar == a,
                      label: 'Avatar $a',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _avatar = a),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _avatar == a
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: Text(a, style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const LanguagePicker(),
              const SizedBox(height: 24),
              AppTextField(
                controller: _name,
                hint: 'Name',
                validator: validateDisplayName,
              ),
              if (email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(email, style: theme.textTheme.bodySmall),
                ),
              _section(theme, 'Goals'),
              _chips(
                goalOptions,
                selected: _goals,
                onTap: (v) => _toggle(_goals, v),
              ),
              _section(theme, 'Workout styles'),
              _chips(
                styleOptions,
                selected: _styles,
                onTap: (v) => _toggle(_styles, v),
              ),
              _section(theme, 'Experience level'),
              _chips(
                levelOptions,
                selected: {?_level},
                onTap: (v) => setState(() => _level = v),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                onPressed: _canSave ? _save : null,
                loading: _busy,
                label: 'Save changes',
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _signOut,
                child: Text(context.tr('Sign out')),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: _busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => const _DeleteAccountDialog(),
                      ),
                child: Text(context.tr('Delete account')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      context.tr(title),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _chips(
    List<ProfileOption> options, {
    required Set<String> selected,
    required ValueChanged<String> onTap,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in options)
        FilterChip(
          label: Text(context.tr(o.label)),
          selected: selected.contains(o.label),
          onSelected: (_) => onTap(o.label),
        ),
    ],
  );
}

/// Confirms, then deletes the account. Errors show inside the dialog; on
/// success the router sends the now signed-out user to login.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) Navigator.pop(context);
    } on AuthFailure catch (e) {
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.tr('Delete account?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'This permanently deletes your account, your scores and your history. It cannot be undone.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _busy ? null : _delete,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.tr('Delete')),
        ),
      ],
    );
  }
}
