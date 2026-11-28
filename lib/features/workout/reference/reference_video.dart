import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

/// Where the trainer video can be shown: media_kit on Windows, video_player on
/// Android/iOS/macOS.
bool get referenceVideoSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

bool get _useMediaKit => defaultTargetPlatform == TargetPlatform.windows;

/// Plays the trainer video next to the camera. The workout owns the timing:
/// it restarts the video with each set and pauses it with the workout, so the
/// trainer on screen and the timeline the user is scored against stay together.
class ReferenceVideo {
  ReferenceVideo(this._asset);

  final String _asset;
  Player? _player;
  VideoController? _controller;
  VideoPlayerController? _vpController;
  bool _disposed = false;

  /// Loads the clip and leaves its first frame on screen (paused), so the
  /// trainer is visible before the countdown starts.
  Future<void> open() async {
    if (_useMediaKit) {
      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _controller = controller;
      // Wait for the native video texture to be created before opening media,
      // otherwise the first frame can decode before the texture is attached.
      await controller.platform.future;
      if (_disposed) return;
      await player.setVolume(0);
      await player.open(Media('asset:///$_asset'), play: true);
      await Future.any([
        controller.waitUntilFirstFrameRendered,
        player.stream.width.firstWhere((w) => w != null && w > 0),
      ]).timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (_disposed) return;
      await player.pause();
      await player.seek(Duration.zero);
    } else {
      final vp = VideoPlayerController.asset(_asset);
      _vpController = vp;
      await vp.initialize();
      if (_disposed) return;
      await vp.setVolume(0);
      await vp.setLooping(false);
      await vp.seekTo(Duration.zero);
      await vp.pause();
    }
  }

  /// Width / height of the video (16:9 until it is known).
  double get aspect {
    if (_useMediaKit) {
      final w = _player?.state.width, h = _player?.state.height;
      return (w == null || h == null || w <= 0 || h <= 0) ? 16 / 9 : w / h;
    }
    final vp = _vpController;
    if (vp == null || !vp.value.isInitialized) return 16 / 9;
    final a = vp.value.aspectRatio;
    return a > 0 ? a : 16 / 9;
  }

  Future<void> restart() async {
    if (_disposed) return;
    if (_useMediaKit) {
      await _player?.seek(Duration.zero);
      await _player?.play();
    } else {
      await _vpController?.seekTo(Duration.zero);
      await _vpController?.play();
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    if (_useMediaKit) {
      await _player?.play();
    } else {
      await _vpController?.play();
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    if (_useMediaKit) {
      await _player?.pause();
    } else {
      await _vpController?.pause();
    }
  }

  Widget view({double radius = 12, BoxFit fit = BoxFit.contain}) =>
      ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: Colors.black,
            child: _useMediaKit
                ? Video(
                    controller: _controller!,
                    controls: NoVideoControls,
                    fit: fit,
                  )
                : FittedBox(
                    fit: fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: aspect * 1000,
                      height: 1000,
                      child: VideoPlayer(_vpController!),
                    ),
                  ),
          ),
        ),
      );

  Future<void> dispose() async {
    _disposed = true;
    await _player?.dispose();
    await _vpController?.dispose();
  }
}
