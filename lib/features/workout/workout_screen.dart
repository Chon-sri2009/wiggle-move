import 'dart:async';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

import 'package:video_player/video_player.dart';

import '../../shared/backend/auth_providers.dart';
import '../../shared/backend/sessions_providers.dart';
import '../../shared/uuid.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/backend/content_models.dart';
import '../../shared/backend/routine_video.dart';
import '../../shared/pose/pose_math.dart';
import '../summary/summary_screen.dart';
import 'camera_failure.dart';
import 'form/form_feedback.dart';
import 'play_clock.dart';
import 'pose_service.dart' show poseDetectionSupported;
import 'reference/reference_clips.dart';
import 'reference/reference_video.dart';
import 'workout_camera.dart';
import 'workout_cues.dart';
import 'workout_session.dart';
import '../../shared/l10n/app_language.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key, required this.routine});
  final Routine routine;

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen>
    with WidgetsBindingObserver {
  late final WorkoutSession _session = WorkoutSession(widget.routine);
  late final _clock = PlayClock(ref.read(playNowMsProvider));
  WorkoutCamera? _camera;
  ReferenceVideo? _video;
  Timer? _timer;
  CameraFailure? _failure;
  int _countdown = 3;
  bool _running = false;
  bool _paused = false;
  bool _finished = false;
  double _live = 0;
  String _segment = '';
  String _videoSet = '';

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
      final camera = ref.read(workoutCameraFactoryProvider)();
      _camera = camera;
      await camera.open();
      await _loadReference();
      if (!mounted) return;
      setState(() {});
      _cues.countdownTick();
      _timer = Timer.periodic(const Duration(seconds: 1), _onCountdown);
    } on NoCameraException {
      _fail(noCameraFailure);
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

  /// Loads the routine's trainer timeline (and, where supported, its video).
  /// Without them the workout is judged against the moves' fixed targets.
  Future<void> _loadReference() async {
    final clip = await ref.read(
      referenceClipProvider(widget.routine.id).future,
    );
    if (clip == null) return;
    _session.reference = clip;
    final asset = referenceAssets[widget.routine.id];
    if (asset != null && referenceVideoSupported && _video == null) {
      final video = ReferenceVideo(asset.video);
      _video = video;
      try {
        await video.open();
      } catch (e) {
        debugPrint('Trainer video could not load: $e');
        _video = null; // the workout does not depend on the video
        unawaited(video.dispose());
      }
    }
  }

  void _fail(CameraFailure failure) {
    _timer?.cancel();
    if (mounted) setState(() => _failure = failure);
  }

  /// Starts over after a failed camera start (e.g. permission now allowed).
  Future<void> _retry() async {
    final camera = _camera;
    _camera = null;
    setState(() {
      _failure = null;
      _countdown = 3;
    });
    await camera?.close();
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
    _segment =
        '${_session.setIndex}/${_session.moveIndex}/${_session.isResting}';
    _videoSet = '${_session.setIndex}/${_session.isResting}';
    unawaited(_video?.restart());
    unawaited(
      _camera!.startFrames(_onAngles).catchError((_) => _cameraStopped()),
    );
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
    // The trainer video restarts with each set and waits during rests.
    final videoSet = '${_session.setIndex}/${_session.isResting}';
    if (videoSet != _videoSet) {
      _videoSet = videoSet;
      if (_session.isResting) {
        unawaited(_video?.pause());
      } else {
        unawaited(_video?.restart());
      }
    }
    setState(() {});
  }

  void _onAngles(Map<Joint, double> angles) {
    if (!_running || _paused || _finished) return;
    final reps = _session.repCount;
    final score = _session.addFrame(angles);
    if (_session.repCount > reps) _cues.repCounted();
    if (score != null && mounted) setState(() => _live = score);
  }

  void _cameraStopped() => _fail(
    const CameraFailure(
      CameraProblem.other,
      'The camera stopped during your workout. Go back and start again.',
      canRetry: false,
    ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app freezes the workout; coming back shows the pause panel
    // (the user resumes when ready, not mid-move).
    if (state != AppLifecycleState.resumed) _pause();
  }

  void _pause() {
    if (!_running || _paused || _finished) return;
    _clock.pause();
    unawaited(_video?.pause());
    final camera = _camera;
    if (camera != null) unawaited(camera.stopFrames().catchError((_) {}));
    if (mounted) setState(() => _paused = true);
  }

  Future<void> _resume() async {
    if (!_paused || _finished) return;
    try {
      await _camera!.startFrames(_onAngles);
    } catch (_) {
      _cameraStopped();
      return;
    }
    _clock.start();
    if (!_session.isResting) unawaited(_video?.play());
    if (mounted) setState(() => _paused = false);
  }

  /// Back / close: confirm before throwing the play away (nothing is saved).
  Future<void> _askQuit() async {
    final wasPaused = _paused;
    _pause();
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Quit workout?')),
        content: Text(
          context.tr('Your progress for this play will not be saved.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Keep going')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Quit')),
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
    _camera?.close();
    _video?.dispose();
    super.dispose();
  }

  /// The user's camera box: about a quarter of the screen width (the video
  /// is the main picture), between 110 and 240 px.
  double _pipWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.28).clamp(110.0, 240.0);

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
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentDeep,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.pause),
                tooltip: context.tr('Pause workout'),
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
            : camera == null || !camera.isOpen
            ? const LoadingView()
            : Stack(
                fit: StackFit.expand,
                children: [
                  // With a trainer video it is the main picture, dimmed so
                  // the user's own camera (in full contrast) stands out.
                  if (_video != null)
                    _VideoStage(video: _video!)
                  else
                    camera.buildPreview(),
                  if (!_running)
                    Center(
                      child: Semantics(
                        liveRegion: true,
                        label: 'Starting in $_countdown',
                        child: ExcludeSemantics(
                          child: FittedBox(
                            child: Text(
                              '$_countdown',
                              maxLines: 1,
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
                        : _MovePanel(
                            session: _session,
                            live: _live,
                            form: _camera?.formFeedback,
                            advice: _session.advice,
                          ),
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
                  if (_video != null)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                      right: 12,
                      width: _pipWidth(context),
                      child: _CameraBox(camera: camera),
                    ),
                  if (_paused && active)
                    _PausedPanel(onResume: _resume, onQuit: _askQuit),
                ],
              ),
      ),
    );
  }
}

/// The trainer video as the main picture: its own shape (letterboxed, never
/// stretched or cropped), dimmed to 55% so it reads as background.
class _VideoStage extends StatelessWidget {
  const _VideoStage({required this.video});
  final ReferenceVideo video;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: video.aspect,
              child: video.view(radius: 0),
            ),
          ),
          // A dark veil, not Opacity: a video texture can render blank
          // inside an opacity layer.
          const IgnorePointer(child: ColoredBox(color: Color(0x73000000))),
        ],
      ),
    );
  }
}

/// The user's camera in full contrast, small, keeping the camera's own shape.
class _CameraBox extends StatelessWidget {
  const _CameraBox({required this.camera});
  final WorkoutCamera camera;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: camera.previewAspect,
          child: camera.buildPreview(),
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
  const _MovePanel({
    required this.session,
    required this.live,
    this.form,
    this.advice,
  });
  final WorkoutSession session;
  final double live;

  /// What to fix right now ("Bend your left knee more"), or null.
  final String? advice;
  final ValueListenable<FormFeedback?>? form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final move = session.currentMove;
    final total = session.routine.moves.length;
    final color = live >= 0.8
        ? AppColors.successOnDark
        : (live >= 0.5 ? AppColors.warningOnDark : AppColors.dangerOnDark);
    final liveLabel = live >= 0.8
        ? 'Good'
        : (live >= 0.5 ? 'Adjust' : 'Off target');
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
                    ? AppColors.successOnDark
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (form case final form?)
          ValueListenableBuilder<FormFeedback?>(
            valueListenable: form,
            builder: (context, feedback, _) {
              if (feedback == null ||
                  !feedbackAppliesToMove(feedback, move.name)) {
                return const SizedBox.shrink();
              }
              final good = feedback.verdict == FormVerdict.good;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    feedback.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: good
                          ? AppColors.successOnDark
                          : AppColors.warningOnDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        if (advice case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              label: 'Warning: $text',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.dangerOnDark,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.dangerOnDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Gap.m),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Form: $liveLabel',
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Semantics(
          label: 'Form match',
          value: '${(live * 100).round()} percent',
          excludeSemantics: true,
          child: LinearProgressIndicator(
            value: live,
            minHeight: 10,
            color: color,
            backgroundColor: Colors.white54,
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
                context.tr('Paused'),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onResume,
              child: Text(context.tr('Resume')),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onQuit,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: Text(context.tr('Quit workout')),
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
              FilledButton(
                onPressed: onRetry,
                child: Text(context.tr('Try again')),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: Text(context.tr('Back')),
            ),
          ],
        ),
      ),
    );
  }
}
