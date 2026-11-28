import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Where the trainer video can be shown (media_kit, bundled with the Windows
/// build). Phones keep using the plain demo clip of `routines.video_path`.
bool get referenceVideoSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Plays the trainer video next to the camera. The workout owns the timing:
/// it restarts the video with each set and pauses it with the workout, so the
/// trainer on screen and the timeline the user is scored against stay together.
class ReferenceVideo {
  ReferenceVideo(this._asset);

  final String _asset;
  final _player = Player();

  /// Created together with the player, before any media is opened: on
  /// Windows the video texture must exist while the first frame is decoded,
  /// or the picture stays black until the next frame.
  late final VideoController _controller = VideoController(_player);

  /// Loads the clip and leaves its first frame on screen (paused), so the
  /// trainer is visible before the countdown starts.
  Future<void> open() async {
    // Touch the controller first so its texture is ready (see above).
    _controller;
    await _player.setVolume(0);
    await _player.open(Media('asset:///$_asset'), play: true);
    // A paused, never-played video shows nothing: play until the first frame
    // is decoded, then stop at the start.
    await _player.stream.width
        .firstWhere((w) => w != null && w > 0)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  /// Width / height of the video (16:9 until it is known).
  double get aspect {
    final w = _player.state.width, h = _player.state.height;
    return (w == null || h == null || w <= 0 || h <= 0) ? 16 / 9 : w / h;
  }

  Future<void> restart() async {
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Widget view({double radius = 12}) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: Colors.black,
        child: Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );

  Future<void> dispose() => _player.dispose();
}
