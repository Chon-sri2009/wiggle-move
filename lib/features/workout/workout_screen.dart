import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/uuid.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/routine_video.dart';
import '../summary/summary_screen.dart';
import 'camera_failure.dart';
import 'play_clock.dart';
import 'pose_service.dart';
import 'workout_cues.dart';
import 'workout_session.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key, required this.routine});
  final Routine routine;

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen>
    with WidgetsBindingObserver {
  late final WorkoutSession _session = WorkoutSession(widget.routine);
  final _wall = Stopwatch()..start();
  late final _clock = PlayClock(() => _wall.elapsedMilliseconds);
  CameraController? _camera;
  PoseService? _pose;
  Timer? _timer;
  CameraFailure? _failure;
  int _countdown = 3;
  bool _running = false;
  bool _paused = false;
  bool _finished = false;
  bool _detecting = false;
  double _live = 0;
  String _segment = '';

  WorkoutCues get _cues => ref.read(workoutCuesProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    if (!poseDetectionSupported) {
      _failure = unsupportedPlatformFailure;
      return;
    }
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        _fail(noCameraFailure);
        return;
      }
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
      _cues.countdownTick();
      _timer = Timer.periodic(const Duration(seconds: 1), _onCountdown);
    } on CameraException catch (e) {
      _fail(cameraFailureFor(e.code, e.description));
    } catch (_) {
      _fail(
        const CameraFailure(
          CameraProblem.other,
          'Could not start the camera. Try again.',
          canRetry: true,
        ),
      );
    }
  }

  void _fail(CameraFailure failure) {
    _timer?.cancel();
    if (mounted) setState(() => _failure = failure);
  }

  /// Starts over after a failed camera start (e.g. permission now allowed).
  Future<void> _retry() async {
    final camera = _camera;
    final pose = _pose;
    _camera = null;
    _pose = null;
    setState(() {
      _failure = null;
      _countdown = 3;
    });
    await camera?.dispose();
    await pose?.close();
    if (mounted) await _init();
  }

  void _onCountdown(Timer timer) {
    if (_countdown > 1) {
      setState(() => _countdown--);
      _cues.countdownTick();
      return;
    }
    timer.cancel();
    setState(() {
      _countdown = 0;
      _running = true;
    });
    _cues.go();
    _clock.start();
    _camera!.startImageStream(_onFrame);
    _timer = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _onTick(Timer timer) {
    if (_paused || _finished) return;
    _session.advance(_clock.elapsedMs);
    if (_session.isDone) {
      _finish();
      return;
    }
    final segment =
        '${_session.setIndex}/${_session.moveIndex}/${_session.isResting}';
    if (segment != _segment) {
      if (_segment.isNotEmpty) _cues.segmentChanged();
      _segment = segment;
    }
    setState(() {});
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_detecting || !_running || _paused || _finished) return;
    _detecting = true;
    try {
      final angles = await _pose!.detect(image, _camera!.description);
      if (angles == null || _paused || _finished) return;
      final reps = _session.repCount;
      final score = _session.addFrame(angles);
      if (_session.repCount > reps) _cues.repCounted();
      if (score != null && mounted) setState(() => _live = score);
    } finally {
      _detecting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app freezes the workout; coming back shows the pause panel
    // (the user resumes when ready, not mid-move).
    if (state != AppLifecycleState.resumed) _pause();
  }

  void _pause() {
    if (!_running || _paused || _finished) return;
    _clock.pause();
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      unawaited(camera.stopImageStream().catchError((_) {}));
    }
    if (mounted) setState(() => _paused = true);
  }

  Future<void> _resume() async {
    if (!_paused || _finished) return;
    try {
      await _camera!.startImageStream(_onFrame);
    } catch (_) {
      _fail(
        const CameraFailure(
          CameraProblem.other,
          'The camera stopped during your workout. Go back and start again.',
          canRetry: false,
        ),
      );
      return;
    }
    _clock.start();
    if (mounted) setState(() => _paused = false);
  }

  /// Back / close: confirm before throwing the play away (nothing is saved).
  Future<void> _askQuit() async {
    final wasPaused = _paused;
    _pause();
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit workout?'),
        content: const Text('Your progress for this play will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (quit == true) {
      _finished = true;
      _timer?.cancel();
      context.pop();
    } else if (!wasPaused) {
      await _resume();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _clock.pause();
    _cues.finished();
    final summary = _session.summary(durationMs: _clock.elapsedMs);
    final userId = ref.read(authUserProvider)?.id;
    String? nonce;
    if (userId != null) {
      // One nonce per play: the queue resends this same submission, so the
      // server stores it at most once. duration_ms is the measured play time
      // without pauses (the timeline ends at the routine length, so it is
      // ~1.0x of it; the server accepts 0.8x..3x).
      nonce = uuidV4();
      final submission = summary.toSubmission(
        userId: userId,
        clientNonce: nonce,
        durationMs: _clock.elapsedMs,
        playedAt: DateTime.now(),
      );
      // Not awaited: the summary shows the upload status as it changes.
      unawaited(ref.read(sessionSyncProvider).submit(submission));
    }
    if (mounted) {
      context.pushReplacement(
        '/summary',
        extra: SummaryArgs(summary, submissionId: nonce),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _camera?.dispose();
    _pose?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final failure = _failure;
    final active = _running && !_finished && !_session.isDone;
    return PopScope(
      canPop: failure != null || !_running || _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askQuit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.routine.name),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          actions: [
            if (active && !_paused)
              IconButton(
                icon: const Icon(Icons.pause),
                tooltip: 'Pause workout',
                onPressed: _pause,
              ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: failure != null
            ? ProblemView(
                failure: failure,
                onRetry: failure.canRetry ? _retry : null,
              )
            : camera == null || !camera.value.isInitialized
            ? const LoadingView()
            : Stack(
                fit: StackFit.expand,
                children: [
                  _Preview(camera),
                  if (!_running)
                    Center(
                      child: Semantics(
                        liveRegion: true,
                        label: 'Starting in $_countdown',
                        child: ExcludeSemantics(
                          child: FittedBox(
                            child: Text(
                              '$_countdown',
                              style: Theme.of(context).textTheme.displayLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontSize: 120,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (active)
                    _session.isResting
                        ? _RestPanel(session: _session)
                        : _MovePanel(session: _session, live: _live),
                  if (active &&
                      routineVideoUrl(widget.routine.videoPath) != null)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                      right: 12,
                      width: 120,
                      child: _Clip(
                        url: routineVideoUrl(widget.routine.videoPath)!,
                        playing: !_paused && !_session.isResting,
                      ),
                    ),
                  if (_paused && active)
                    _PausedPanel(onResume: _resume, onQuit: _askQuit),
                ],
              ),
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
    return ExcludeSemantics(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(camera),
          ),
        ),
      ),
    );
  }
}

/// The routine's demonstration clip: muted, looping, playing only while the
/// workout runs. Shows nothing if the video cannot load (the workout never
/// depends on it).
class _Clip extends StatefulWidget {
  const _Clip({required this.url, required this.playing});
  final String url;
  final bool playing;

  @override
  State<_Clip> createState() => _ClipState();
}

class _ClipState extends State<_Clip> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) async {
          await _controller.setLooping(true);
          await _controller.setVolume(0);
          if (!mounted) return;
          setState(() => _ready = true);
          _sync();
        })
        .catchError((_) {});
  }

  @override
  void didUpdateWidget(_Clip old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    if (!_ready) return;
    widget.playing ? _controller.play() : _controller.pause();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return Semantics(
      label: 'Demonstration video',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}

/// The dark card at the bottom. It scrolls instead of overflowing when the
/// system text size is large.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
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
    final header = [
      if (session.routine.sets > 1)
        'Set ${session.setIndex + 1} of ${session.routine.sets}',
      'Move ${session.moveIndex + 1} of $total',
    ].join(' · ');
    return _Panel(
      children: [
        // One live region: a screen reader announces each new move once.
        Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            children: [
              Text(
                header,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                move.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              Text(
                move.instruction,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        if (move.rep case final rep?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              'Reps ${session.repCount} / ${rep.target}',
              style: theme.textTheme.displaySmall?.copyWith(
                color: session.repCount >= rep.target
                    ? Colors.green
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Semantics(
          label: 'Form match',
          value: '${(live * 100).round()} percent',
          excludeSemantics: true,
          child: LinearProgressIndicator(
            value: live,
            minHeight: 10,
            color: color,
            backgroundColor: Colors.white24,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ],
    );
  }
}

/// Between sets: counts the rest down and names what comes next.
class _RestPanel extends StatelessWidget {
  const _RestPanel({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = (session.restRemainingMs / 1000).ceil();
    return _Panel(
      children: [
        // Only the heading is live: announcing every second would be noise.
        Semantics(
          liveRegion: true,
          child: Text(
            'Rest · set ${session.setIndex + 2} of ${session.routine.sets} next',
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
          ),
        ),
        Text(
          '$seconds s',
          style: theme.textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          'Next: ${session.currentMove.name}',
          style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

class _PausedPanel extends StatelessWidget {
  const _PausedPanel({required this.onResume, required this.onQuit});
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                'Paused',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onResume, child: const Text('Resume')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onQuit,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Quit workout'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The camera could not be used: says why and offers Try again when that can
/// help (e.g. after allowing the permission).
class ProblemView extends StatelessWidget {
  const ProblemView({super.key, required this.failure, this.onRetry});
  final CameraFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
