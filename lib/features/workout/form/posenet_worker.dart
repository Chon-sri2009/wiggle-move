import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'frame_preprocess.dart';
import 'posenet_engine.dart';

/// Runs [PoseNetEngine] on its own isolate so a ~0.3 s inference never
/// freezes the UI. One request at a time.
class PoseNetWorker {
  PoseNetWorker._(this._isolate, this._commands, this._replies);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  Completer<PoseNetOutput>? _pending;

  static Future<PoseNetWorker> start(
    Uint8List posenetWeights,
    Uint8List headWeights,
  ) async {
    final replies = ReceivePort();
    final events = replies.asBroadcastStream();
    final isolate = await Isolate.spawn(
      _entry,
      _Boot(
        replies.sendPort,
        TransferableTypedData.fromList([posenetWeights]),
        TransferableTypedData.fromList([headWeights]),
      ),
    );
    final commands = await events.first as SendPort;
    final worker = PoseNetWorker._(isolate, commands, replies);
    events.listen(worker._onReply);
    return worker;
  }

  void _onReply(dynamic message) {
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    if (message is List) {
      final probabilities = (message[0] as List).cast<double>();
      final flat = (message[1] as List).cast<double>();
      pending.complete(
        PoseNetOutput(
          probabilities: probabilities,
          keypoints: [
            for (var i = 0; i + 2 < flat.length; i += 3)
              PoseKeypoint(flat[i], flat[i + 1], flat[i + 2]),
          ],
        ),
      );
    } else {
      pending.completeError(StateError('pose worker failed: $message'));
    }
  }

  /// [rgb] is 257x257x3 floats (`preprocessFrame`). Ownership moves to the
  /// worker; do not touch the list until this completes.
  Future<PoseNetOutput> run(Float32List rgb) {
    if (_pending != null) {
      throw StateError('pose worker is busy');
    }
    final pending = _pending = Completer<PoseNetOutput>();
    _commands.send(TransferableTypedData.fromList([rgb]));
    return pending.future;
  }

  /// Preprocesses raw RGBA8888 [rgba] ([width] x [height]) on the worker
  /// isolate and runs inference, keeping the UI isolate free of pixel math.
  Future<PoseNetOutput> runRgba(
    Uint8List rgba,
    int width,
    int height, {
    bool mirror = true,
  }) {
    if (_pending != null) {
      throw StateError('pose worker is busy');
    }
    final pending = _pending = Completer<PoseNetOutput>();
    _commands.send([
      TransferableTypedData.fromList([rgba]),
      width,
      height,
      mirror,
    ]);
    return pending.future;
  }

  void close() {
    _pending?.completeError(StateError('pose worker closed'));
    _pending = null;
    _replies.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _Boot {
  _Boot(this.replies, this.posenet, this.head);
  final SendPort replies;
  final TransferableTypedData posenet, head;
}

void _entry(_Boot boot) {
  final engine = PoseNetEngine.fromBytes(
    boot.posenet.materialize().asUint8List(),
    boot.head.materialize().asUint8List(),
  );
  final scratch = Float32List(modelInputSize * modelInputSize * 3);
  final commands = ReceivePort();
  boot.replies.send(commands.sendPort);
  commands.listen((message) {
    try {
      final Float32List input;
      if (message is List) {
        final rgba = (message[0] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final width = message[1] as int;
        final height = message[2] as int;
        final mirror = message[3] as bool;
        input = preprocessFrame(
          width: width,
          height: height,
          pixelAt: (x, y) {
            final i = (y * width + x) * 4;
            return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
          },
          mirror: mirror,
          out: scratch,
        );
      } else {
        input = Float32List.sublistView(
          (message as TransferableTypedData).materialize().asUint8List(),
        );
      }
      final out = engine.run(input);
      boot.replies.send([
        out.probabilities,
        [
          for (final k in out.keypoints) ...[k.x, k.y, k.score],
        ],
      ]);
    } catch (e) {
      boot.replies.send('$e');
    }
  });
}
