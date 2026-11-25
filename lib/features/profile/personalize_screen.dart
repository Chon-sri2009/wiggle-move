import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/backend/profile_repository.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/primary_button.dart';
import 'profile_store.dart';

class _Option {
  const _Option(this.label, this.icon, [this.subtitle]);
  final String label;
  final IconData icon;
  final String? subtitle;
}

const _goals = [
  _Option('Burn Calories', Icons.local_fire_department),
  _Option('Build Strength', Icons.front_hand),
  _Option('Improve Fitness', Icons.monitor_heart),
  _Option('Improve Flexibility', Icons.directions_run),
  _Option('Weight Management', Icons.monitor_weight),
  _Option('Stay Healthy', Icons.health_and_safety),
];

const _styles = [
  _Option('Dance Workout', Icons.accessibility_new),
  _Option('Cardio', Icons.favorite),
  _Option('Bodyweight', Icons.fitness_center),
  _Option('Stretching', Icons.eco),
];

const _levels = [
  _Option('Beginner', Icons.child_care, "I'm just getting started."),
  _Option('Intermediate', Icons.accessibility_new, 'I work out occasionally.'),
  _Option('Advanced', Icons.person, 'I know various workout techniques.'),
];

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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personalization',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "Let's make it personal!",
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tell us a little about yourself so we can create a '
                          'workout experience that fits you.',
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    number,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(subtitle, style: theme.textTheme.bodySmall),
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
      options: _goals,
      columns: 3,
      selected: _goalSel,
      onTap: (v) => _toggle(_goalSel, v),
    ),
    2 => _Grid(
      options: _styles,
      columns: 2,
      selected: _styleSel,
      onTap: (v) => _toggle(_styleSel, v),
    ),
    _ => Column(
      children: [
        for (final o in _levels)
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
  final List<_Option> options;
  final int columns;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: columns == 3 ? 0.85 : 1.2,
      children: [
        for (final o in options)
          _Tile(
            option: o,
            selected: selected.contains(o.label),
            onTap: () => onTap(o.label),
          ),
      ],
    );
  }
}

BoxDecoration _tileDecoration(bool selected, double radius) => BoxDecoration(
  color: AppColors.field,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(
    color: selected ? AppColors.secondary : Colors.transparent,
    width: 3,
  ),
);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final _Option option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: _tileDecoration(selected, 16),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(option.icon, size: 40, color: AppColors.secondary),
              const SizedBox(height: 6),
              Text(
                option.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
  final _Option option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${option.label}. ${option.subtitle}',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: _tileDecoration(selected, 16),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(option.icon, size: 32, color: AppColors.secondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        option.subtitle!,
                        style: const TextStyle(fontSize: 12),
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
