import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/primary_button.dart';
import 'profile_options.dart';
import 'profile_store.dart';
import '../../shared/l10n/app_language.dart';

/// Figma "Personalization" flow: intro, then 01 goal, 02 style, 03 level.
class PersonalizeScreen extends ConsumerStatefulWidget {
  const PersonalizeScreen({super.key});

  @override
  ConsumerState<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends ConsumerState<PersonalizeScreen> {
  int _step = 0; // 0 = intro, 1..3 = questions
  final _goalSel = <String>{};
  final _styleSel = <String>{};
  String? _level;
  bool _saving = false;

  bool get _canContinue => switch (_step) {
    1 => _goalSel.isNotEmpty,
    2 => _styleSel.isNotEmpty,
    3 => _level != null,
    _ => true,
  };

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(profileProvider.notifier)
          .complete(
            goals: _goalSel.toList(),
            styles: _styleSel.toList(),
            level: _level!,
          );
    } on RepositoryFailure catch (e) {
      // Stay on this step so the user can try again.
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, e.message, isError: true);
      }
      return;
    }
    if (mounted) context.go('/');
  }

  void _toggle(Set<String> set, String value) {
    setState(() => set.contains(value) ? set.remove(value) : set.add(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (number, title, subtitle) = switch (_step) {
      1 => ('01', 'Your Fitness Goal', 'What are your fitness goals?'),
      2 => ('02', 'Workout Style', 'What type of workout do you enjoy?'),
      3 => (
        '03',
        'Experience Level',
        'How would you describe your fitness experience?',
      ),
      _ => ('', '', ''),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_step == 0)
                  Expanded(
                    // Centered, but scrolls when large text does not fit.
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('Personalization'),
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: AppColors.accentDeep,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                context.tr('Let\'s make it personal!'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.tr(
                                  'Tell us a little about yourself so we can create a workout experience that fits you.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  Text(
                    number,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: AppColors.accentDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    context.tr(title),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(context.tr(subtitle), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 20),
                  Expanded(child: SingleChildScrollView(child: _stepBody())),
                ],
                Center(
                  child: PrimaryButton(
                    onPressed: _canContinue ? _next : null,
                    loading: _saving,
                    label: switch (_step) {
                      0 => 'Start',
                      3 => 'Create My Workout Plan',
                      _ => 'Next',
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
    1 => _Grid(
      options: goalOptions,
      columns: 3,
      selected: _goalSel,
      onTap: (v) => _toggle(_goalSel, v),
    ),
    2 => _Grid(
      options: styleOptions,
      columns: 2,
      selected: _styleSel,
      onTap: (v) => _toggle(_styleSel, v),
    ),
    _ => Column(
      children: [
        for (final o in levelOptions)
          _LevelRow(
            option: o,
            selected: _level == o.label,
            onTap: () => setState(() => _level = o.label),
          ),
      ],
    ),
  };
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.options,
    required this.columns,
    required this.selected,
    required this.onTap,
  });
  final List<ProfileOption> options;
  final int columns;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    // Larger system text needs wider tiles: a label such as "Management"
    // must not be cut mid-word, so use fewer columns instead.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = MediaQuery.sizeOf(context).width;
    final cols = scale > 1.5
        ? 1
        : (scale > 1.15 || width < 340)
        ? columns.clamp(1, 2)
        : columns;
    // Rows sized by their tallest tile (a fixed aspect ratio overflowed when a
    // label wrapped to a second line).
    return Column(
      children: [
        for (var i = 0; i < options.length; i += cols)
          Padding(
            padding: EdgeInsets.only(
              bottom: i + cols < options.length ? 12 : 0,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + cols; j++) ...[
                    if (j > i) const SizedBox(width: 12),
                    Expanded(
                      child: j < options.length
                          ? _Tile(
                              option: options[j],
                              selected: selected.contains(options[j].label),
                              onTap: () => onTap(options[j].label),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

BoxDecoration _tileDecoration(bool selected, double radius) => BoxDecoration(
  color: AppColors.field,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(
    color: selected ? AppColors.primary : Colors.transparent,
    width: 3,
  ),
);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final ProfileOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr(option.label),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: _tileDecoration(selected, 16),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.check_circle : option.icon,
                    size: IconSize.xl,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(option.label),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final ProfileOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${context.tr(option.label)}. ${context.tr(option.subtitle!)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: _tileDecoration(selected, 16),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : option.icon,
                  size: IconSize.l,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(option.label),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        context.tr(option.subtitle!),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
