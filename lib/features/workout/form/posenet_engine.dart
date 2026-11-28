import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart inference for the Teachable Machine pose model (PoseNet
/// MobileNetV1 0.75, output stride 16, 257 px, plus the 12-class head), used
/// where TFLite and ML Kit do not exist (Windows desktop). No Flutter or
/// plugin imports, so it runs in tests and in an isolate.
///
/// Weights are the original tfjs float32 files; `tool/pose_model/` explains
/// where they come from. Output matches the TFLite model (see the parity
/// test).

const _grid = 17;
const _parts = 17;
const _featureLength = _grid * _grid * (_parts + 2 * _parts); // 14739
const _headHidden = 100;

/// PoseNet part order.
enum PosePart {
  nose,
  leftEye,
  rightEye,
  leftEar,
  rightEar,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

/// One detected body point in the 257x257 model input space.
class PoseKeypoint {
  const PoseKeypoint(this.x, this.y, this.score);
  final double x;
  final double y;
  final double score;
}

class PoseNetOutput {
  const PoseNetOutput({required this.probabilities, required this.keypoints});

  /// One probability per class label.
  final List<double> probabilities;

  /// [PosePart.values] order.
  final List<PoseKeypoint> keypoints;
}

class _Pointwise {
  _Pointwise(this.cin, this.cout, Float32List kernelHwio, this.bias)
    : weights = _transpose(kernelHwio, cin, cout);
  final int cin, cout;
  final Float32List bias;

  /// [cout][cin], so each output channel is one contiguous dot product.
  final Float32List weights;

  static Float32List _transpose(Float32List k, int cin, int cout) {
    final t = Float32List(cin * cout);
    for (var i = 0; i < cin; i++) {
      for (var o = 0; o < cout; o++) {
        t[o * cin + i] = k[i * cout + o];
      }
    }
    return t;
  }
}

class _Depthwise {
  _Depthwise(this.channels, this.stride, this.weights, this.bias);
  final int channels, stride;

  /// [3][3][channels].
  final Float32List weights;
  final Float32List bias;
}

class PoseNetEngine {
  PoseNetEngine._(
    this._stemWeights,
    this._stemBias,
    this._depthwise,
    this._pointwise,
    this._heatmap,
    this._offsets,
    this._k1,
    this._b1,
    this._k2,
  );

  /// [posenetBytes]: the tfjs weight shards concatenated (manifest order);
  /// [headBytes]: the Teachable Machine `model.weights.bin`.
  factory PoseNetEngine.fromBytes(Uint8List posenetBytes, Uint8List headBytes) {
    final floats = Float32List.sublistView(posenetBytes);
    var at = 0;
    Float32List take(int n) {
      // Copied: SIMD views need 16-byte aligned buffers.
      final out = Float32List.fromList(
        Float32List.sublistView(floats, at, at + n),
      );
      at += n;
      return out;
    }

    // Manifest order: offsets head, blocks 13..1 (pointwise, depthwise),
    // stem, heatmap head, then two displacement heads we do not need.
    final offsetBias = take(34);
    final offsetKernel = take(384 * 34);
    const blockIn = [
      0,
      24,
      48,
      96,
      96,
      192,
      192,
      384,
      384,
      384,
      384,
      384,
      384,
      384,
    ];
    const blockOut = [
      0,
      48,
      96,
      96,
      192,
      192,
      384,
      384,
      384,
      384,
      384,
      384,
      384,
      384,
    ];
    final depthwise = List<_Depthwise?>.filled(14, null);
    final pointwise = List<_Pointwise?>.filled(14, null);
    for (var i = 13; i >= 1; i--) {
      final pwBias = take(blockOut[i]);
      final pwKernel = take(blockIn[i] * blockOut[i]);
      final dwBias = take(blockIn[i]);
      final dwKernel = take(9 * blockIn[i]);
      pointwise[i] = _Pointwise(blockIn[i], blockOut[i], pwKernel, pwBias);
      depthwise[i] = _Depthwise(
        blockIn[i],
        (i == 2 || i == 4 || i == 6) ? 2 : 1,
        dwKernel,
        dwBias,
      );
    }
    final stemBias = take(24);
    final stemKernel = take(3 * 3 * 3 * 24);
    final heatBias = take(_parts);
    final heatKernel = take(384 * _parts);

    final head = Float32List.fromList(Float32List.sublistView(headBytes));
    return PoseNetEngine._(
      stemKernel,
      stemBias,
      depthwise.sublist(1).cast<_Depthwise>(),
      pointwise.sublist(1).cast<_Pointwise>(),
      _Pointwise(384, _parts, heatKernel, heatBias),
      _Pointwise(384, 2 * _parts, offsetKernel, offsetBias),
      Float32List.sublistView(head, 0, _featureLength * _headHidden),
      Float32List.sublistView(
        head,
        _featureLength * _headHidden,
        _featureLength * _headHidden + _headHidden,
      ),
      Float32List.sublistView(head, _featureLength * _headHidden + _headHidden),
    );
  }

  final Float32List _stemWeights, _stemBias;
  final List<_Depthwise> _depthwise;
  final List<_Pointwise> _pointwise;
  final _Pointwise _heatmap, _offsets;
  final Float32List _k1, _b1, _k2;

  /// [rgb]: 257x257x3 floats, RGB 0..255 (see `preprocessFrame`).
  PoseNetOutput run(Float32List rgb) {
    final features = featuresOf(rgb);
    return PoseNetOutput(
      probabilities: classify(features),
      keypoints: decodeKeypoints(features),
    );
  }

  /// The 14739 numbers the classifier head reads: sigmoid heatmaps (17) and
  /// offsets (34) per cell of the 17x17 grid, row-major.
  Float32List featuresOf(Float32List rgb) {
    // Stem: 3x3 stride 2, SAME, 3 -> 24, relu6.
    var size = 129;
    var x = Float32List(size * size * 24);
    for (var oy = 0; oy < size; oy++) {
      for (var ox = 0; ox < size; ox++) {
        final outBase = (oy * size + ox) * 24;
        for (var o = 0; o < 24; o++) {
          x[outBase + o] = _stemBias[o];
        }
        for (var ky = 0; ky < 3; ky++) {
          final iy = oy * 2 + ky - 1;
          if (iy < 0 || iy >= 257) continue;
          for (var kx = 0; kx < 3; kx++) {
            final ix = ox * 2 + kx - 1;
            if (ix < 0 || ix >= 257) continue;
            final inBase = (iy * 257 + ix) * 3;
            for (var c = 0; c < 3; c++) {
              final v = rgb[inBase + c] / 127.5 - 1.0;
              final wBase = ((ky * 3 + kx) * 3 + c) * 24;
              for (var o = 0; o < 24; o++) {
                x[outBase + o] += v * _stemWeights[wBase + o];
              }
            }
          }
        }
        for (var o = 0; o < 24; o++) {
          x[outBase + o] = _relu6(x[outBase + o]);
        }
      }
    }

    for (var i = 0; i < _depthwise.length; i++) {
      final dw = _depthwise[i];
      final out = _depthwiseConv(x, size, dw);
      size = (size + dw.stride - 1) ~/ dw.stride;
      x = _pointwiseConv(out, size * size, _pointwise[i], relu: true);
    }

    final heat = _pointwiseConv(x, size * size, _heatmap, relu: false);
    final off = _pointwiseConv(x, size * size, _offsets, relu: false);
    final features = Float32List(_featureLength);
    for (var cell = 0; cell < _grid * _grid; cell++) {
      final base = cell * (3 * _parts);
      for (var k = 0; k < _parts; k++) {
        features[base + k] = 1.0 / (1.0 + math.exp(-heat[cell * _parts + k]));
      }
      for (var k = 0; k < 2 * _parts; k++) {
        features[base + _parts + k] = off[cell * 2 * _parts + k];
      }
    }
    return features;
  }

  /// The classifier head: Dense(100, relu) then Dense(12, softmax, no bias).
  List<double> classify(Float32List features) {
    final hidden = Float32List(_headHidden)..setAll(0, _b1);
    final h4 = Float32x4List.view(hidden.buffer);
    final k4 = Float32x4List.view(
      _k1.buffer,
      _k1.offsetInBytes,
      _k1.length ~/ 4,
    );
    const row4 = _headHidden ~/ 4;
    for (var i = 0; i < _featureLength; i++) {
      final f = features[i];
      if (f == 0) continue;
      final fv = Float32x4.splat(f);
      final base = i * row4;
      for (var j = 0; j < row4; j++) {
        h4[j] += fv * k4[base + j];
      }
    }
    for (var j = 0; j < _headHidden; j++) {
      if (hidden[j] < 0) hidden[j] = 0;
    }
    final classes = _k2.length ~/ _headHidden;
    final logits = List<double>.filled(classes, 0);
    for (var j = 0; j < _headHidden; j++) {
      final h = hidden[j];
      if (h == 0) continue;
      for (var c = 0; c < classes; c++) {
        logits[c] += h * _k2[j * classes + c];
      }
    }
    final top = logits.reduce(math.max);
    var sum = 0.0;
    for (var c = 0; c < classes; c++) {
      logits[c] = math.exp(logits[c] - top);
      sum += logits[c];
    }
    return [for (final l in logits) l / sum];
  }

  /// Single-person keypoints: the strongest heatmap cell per part, refined
  /// with its offset vector (PoseNet's `getPointsConfidence` for one pose).
  List<PoseKeypoint> decodeKeypoints(Float32List features) {
    return [
      for (var k = 0; k < _parts; k++)
        () {
          var best = -1.0;
          var br = 0, bc = 0;
          for (var r = 0; r < _grid; r++) {
            for (var c = 0; c < _grid; c++) {
              final s = features[(r * _grid + c) * 51 + k];
              if (s > best) {
                best = s;
                br = r;
                bc = c;
              }
            }
          }
          final base = (br * _grid + bc) * 51 + _parts;
          return PoseKeypoint(
            bc * 16 + features[base + _parts + k],
            br * 16 + features[base + k],
            best,
          );
        }(),
    ];
  }

  static double _relu6(double v) => v < 0 ? 0 : (v > 6 ? 6 : v);

  static Float32List _depthwiseConv(Float32List x, int size, _Depthwise dw) {
    final c = dw.channels;
    final c4 = c ~/ 4;
    final outSize = (size + dw.stride - 1) ~/ dw.stride;
    final padTotal = math.max((outSize - 1) * dw.stride + 3 - size, 0);
    final padBefore = padTotal ~/ 2;
    final out = Float32List(outSize * outSize * c);
    final x4 = Float32x4List.view(x.buffer);
    final o4 = Float32x4List.view(out.buffer);
    final w4 = Float32x4List.view(
      dw.weights.buffer,
      dw.weights.offsetInBytes,
      dw.weights.length ~/ 4,
    );
    final b4 = Float32x4List.view(
      dw.bias.buffer,
      dw.bias.offsetInBytes,
      dw.bias.length ~/ 4,
    );
    final zero = Float32x4.zero();
    final six = Float32x4.splat(6);
    for (var oy = 0; oy < outSize; oy++) {
      for (var ox = 0; ox < outSize; ox++) {
        final ob = (oy * outSize + ox) * c4;
        for (var k = 0; k < c4; k++) {
          o4[ob + k] = b4[k];
        }
        for (var ky = 0; ky < 3; ky++) {
          final iy = oy * dw.stride + ky - padBefore;
          if (iy < 0 || iy >= size) continue;
          for (var kx = 0; kx < 3; kx++) {
            final ix = ox * dw.stride + kx - padBefore;
            if (ix < 0 || ix >= size) continue;
            final ib = (iy * size + ix) * c4;
            final wb = (ky * 3 + kx) * c4;
            for (var k = 0; k < c4; k++) {
              o4[ob + k] += x4[ib + k] * w4[wb + k];
            }
          }
        }
        for (var k = 0; k < c4; k++) {
          o4[ob + k] = o4[ob + k].max(zero).min(six);
        }
      }
    }
    return out;
  }

  static Float32List _pointwiseConv(
    Float32List x,
    int pixels,
    _Pointwise pw, {
    required bool relu,
  }) {
    final c4 = pw.cin ~/ 4;
    final out = Float32List(pixels * pw.cout);
    final x4 = Float32x4List.view(x.buffer);
    final w4 = Float32x4List.view(pw.weights.buffer);
    for (var p = 0; p < pixels; p++) {
      final xb = p * c4;
      for (var o = 0; o < pw.cout; o++) {
        final wb = o * c4;
        var acc = Float32x4.zero();
        for (var k = 0; k < c4; k++) {
          acc += x4[xb + k] * w4[wb + k];
        }
        final v = acc.x + acc.y + acc.z + acc.w + pw.bias[o];
        out[p * pw.cout + o] = relu ? _relu6(v) : v;
      }
    }
    return out;
  }
}
