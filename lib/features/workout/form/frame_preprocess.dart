import 'dart:typed_data';

/// Side of the square image the model takes.
const modelInputSize = 257;

/// Reads the colour at raw frame coordinates, packed as 0xRRGGBB.
typedef PixelAt = int Function(int x, int y);

/// A pixel reader for an NV21 frame (Android camera format).
PixelAt nv21Pixels(Uint8List bytes, int width, int height, int bytesPerRow) {
  final uvStart = height * bytesPerRow;
  return (x, y) {
    final yy = bytes[y * bytesPerRow + x];
    final uv = uvStart + (y >> 1) * bytesPerRow + (x & ~1);
    final v = bytes[uv] - 128;
    final u = bytes[uv + 1] - 128;
    return _pack(
      yy + 1.402 * v,
      yy - 0.344136 * u - 0.714136 * v,
      yy + 1.772 * u,
    );
  };
}

/// A pixel reader for a BGRA frame (iOS camera format).
PixelAt bgraPixels(Uint8List bytes, int bytesPerRow) {
  return (x, y) {
    final i = y * bytesPerRow + x * 4;
    return (bytes[i + 2] << 16) | (bytes[i + 1] << 8) | bytes[i];
  };
}

int _pack(double r, double g, double b) =>
    (_clamp(r) << 16) | (_clamp(g) << 8) | _clamp(b);

int _clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// Builds the model input the way the original Teachable Machine pose library
/// does: the upright frame is padded with black to a square, resized to
/// [modelInputSize] with bilinear interpolation (TensorFlow.js' legacy
/// sampling, no half-pixel offset), and laid out as RGB 0..255 floats.
///
/// [rotationDegrees] is how far the raw frame must turn clockwise to be
/// upright (the camera's sensor orientation). [mirror] flips it left to
/// right: the model was trained on mirrored webcam images, so front-camera
/// frames, which arrive unmirrored, need it.
Float32List preprocessFrame({
  required int width,
  required int height,
  required PixelAt pixelAt,
  int rotationDegrees = 0,
  bool mirror = false,
  Float32List? out,
}) {
  final turned = rotationDegrees == 90 || rotationDegrees == 270;
  final uw = turned ? height : width;
  final uh = turned ? width : height;

  var padT = 0, padL = 0;
  if (uw < uh) {
    padL = ((uh - uw) * 0.5).round();
  } else {
    padT = ((uw - uh) * 0.5).round();
  }
  final pw = uw + 2 * padL;
  final ph = uh + 2 * padT;

  int rgbAt(int px, int py) {
    var ux = px - padL;
    final uy = py - padT;
    if (ux < 0 || ux >= uw || uy < 0 || uy >= uh) return 0;
    if (mirror) ux = uw - 1 - ux;
    return switch (rotationDegrees) {
      90 => pixelAt(uy, height - 1 - ux),
      180 => pixelAt(width - 1 - ux, height - 1 - uy),
      270 => pixelAt(width - 1 - uy, ux),
      _ => pixelAt(ux, uy),
    };
  }

  final result = out ?? Float32List(modelInputSize * modelInputSize * 3);
  final scaleX = pw / modelInputSize;
  final scaleY = ph / modelInputSize;
  var o = 0;
  for (var oy = 0; oy < modelInputSize; oy++) {
    final sy = oy * scaleY;
    final y0 = sy.floor();
    final y1 = sy.ceil() < ph - 1 ? sy.ceil() : ph - 1;
    final fy = sy - y0;
    for (var ox = 0; ox < modelInputSize; ox++) {
      final sx = ox * scaleX;
      final x0 = sx.floor();
      final x1 = sx.ceil() < pw - 1 ? sx.ceil() : pw - 1;
      final fx = sx - x0;
      final tl = rgbAt(x0, y0);
      final tr = rgbAt(x1, y0);
      final bl = rgbAt(x0, y1);
      final br = rgbAt(x1, y1);
      for (var shift = 16; shift >= 0; shift -= 8) {
        final a = (tl >> shift) & 0xff;
        final b = (tr >> shift) & 0xff;
        final c = (bl >> shift) & 0xff;
        final d = (br >> shift) & 0xff;
        final top = a + (b - a) * fx;
        final bottom = c + (d - c) * fx;
        result[o++] = top + (bottom - top) * fy;
      }
    }
  }
  return result;
}
