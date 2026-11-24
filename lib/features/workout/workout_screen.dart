import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../leaderboard/leaderboard_store.dart';
import '../trainers/trainer.dart';
import 'pose_service.dart';
import 'workout_session.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key, required this.routine});
  final Routine routine;

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  late final WorkoutSession _session = WorkoutSession(widget.routine);
  final _stopwatch = Stopwatch();
  CameraController? _camera;
  PoseService? _pose;
  Timer? _timer;
  String? _error;
  int _countdown = 3;
  bool _running = false;
  bool _finished = false;
  bool _detecting = false;
  double _live = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!poseDetectionSupported) {
      _error = 'Pose detection runs on Android and iOS only. Open the app on a phone.';
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera found on this device.');
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: poseImageFormat,
      );
      _camera = camera;
      await camera.initialize();
      if (!mounted) return;
      _pose = PoseService();
      setState(() {});
      _timer = Timer.periodic(const Duration(seconds: 1), _onCountdown);
    } on CameraException catch (e) {
      _fail(
        e.code.contains('Denied')
            ? 'Camera permission is needed to check your moves. Enable it in Settings.'
            : 'Camera problem: ${e.description ?? e.code}',
      );
    } catch (e) {
      _fail('Could not start: $e');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onCountdown(Timer timer) {
    if (_countdown > 1) {
      setState(() => _countdown--);
      return;
    }
    timer.cancel();
    setState(() {
      _countdown = 0;
      _running = true;
    });
    _stopwatch.start();
    _camera!.startImageStream(_onFrame);
    _timer = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _onTick(Timer timer) {
    _session.advance(_stopwatch.elapsedMilliseconds);
    if (_session.isDone) {
      _finish();
    } else {
      setState(() {});
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_detecting || !_running || _finished) return;
    _detecting = true;
    try {
      final angles = await _pose!.detect(image, _camera!.description);
      if (angles == null || _finished) return;
      final score = _session.addFrame(angles);
      if (score != null && mounted) setState(() => _live = score);
    } finally {
      _detecting = false;
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    final summary = _session.summary();
    final name = ref.read(playerNameProvider);
    if (name != null) {
      await ref
          .read(leaderboardProvider.notifier)
          .add(
            LeaderboardEntry(
              playerName: name,
              routineId: widget.routine.id,
              score: summary.totalScore,
              playedAt: DateTime.now(),
            ),
          );
    }
    if (mounted) context.pushReplacement('/summary', extra: summary);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    _pose?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.routine.name),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: _error != null
          ? _Message(_error!)
          : camera == null || !camera.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                _Preview(camera),
                if (!_running)
                  Center(
                    child: Text(
                      '$_countdown',
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 120,
                      ),
                    ),
                  ),
                if (_running && !_session.isDone)
                  _MovePanel(session: _session, live: _live),
              ],
            ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview(this.camera);
  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final size = camera.value.previewSize!;
    // Preview size is reported in landscape; the app is portrait-locked.
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(camera),
        ),
      ),
    );
  }
}

class _MovePanel extends StatelessWidget {
  const _MovePanel({required this.session, required this.live});
  final WorkoutSession session;
  final double live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final move = session.currentMove;
    final total = session.routine.moves.length;
    final color = live >= 0.8
        ? Colors.green
        : (live >= 0.5 ? Colors.orange : Colors.red);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Move ${session.moveIndex + 1} of $total',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              move.name,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            Text(
              move.instruction,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: live,
              minHeight: 10,
              color: color,
              backgroundColor: Colors.white24,
              borderRadius: BorderRadius.circular(5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    ),
  );
}
