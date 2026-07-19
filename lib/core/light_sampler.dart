import 'package:camera/camera.dart';

/// Extracts an average brightness (0-255) from a camera frame as cheaply
/// as possible, without decoding to a full RGB image.
///
/// - On Android, `camera` streams YUV420 frames: plane 0 is the Y
///   (luma/brightness) plane already — no color math needed.
/// - On iOS, `camera` streams BGRA8888 frames: we cheaply approximate
///   luminance from the B/G/R bytes.
///
/// Only a stride-sampled subset of pixels from the center of the frame is
/// read, both for speed and because the receiver is meant to be pointed
/// so the transmitting flash fills roughly the center of frame.
double sampleCenterLuminance(CameraImage image, {int stride = 6}) {
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
      return _sampleYuv420(image, stride);
    case ImageFormatGroup.bgra8888:
      return _sampleBgra8888(image, stride);
    default:
      // Fallback: just average raw bytes of the first plane. Not accurate
      // luminance, but keeps the app functional on an unexpected format.
      final bytes = image.planes.first.bytes;
      int sum = 0;
      int count = 0;
      for (int i = 0; i < bytes.length; i += stride) {
        sum += bytes[i];
        count++;
      }
      return count == 0 ? 0 : sum / count;
  }
}

double _sampleYuv420(CameraImage image, int stride) {
  final plane = image.planes[0]; // Y plane = luminance
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;
  final width = image.width;
  final height = image.height;

  // Sample a centered box covering the middle ~40% of the frame, since
  // that's where we ask the user to aim the crosshair at the other torch.
  final boxW = (width * 0.4).round();
  final boxH = (height * 0.4).round();
  final startX = (width - boxW) ~/ 2;
  final startY = (height - boxH) ~/ 2;

  int sum = 0;
  int count = 0;
  for (int y = startY; y < startY + boxH; y += stride) {
    final rowOffset = y * rowStride;
    for (int x = startX; x < startX + boxW; x += stride) {
      sum += bytes[rowOffset + x];
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

double _sampleBgra8888(CameraImage image, int stride) {
  final plane = image.planes[0];
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;
  final width = image.width;
  final height = image.height;

  final boxW = (width * 0.4).round();
  final boxH = (height * 0.4).round();
  final startX = (width - boxW) ~/ 2;
  final startY = (height - boxH) ~/ 2;

  int sum = 0;
  int count = 0;
  for (int y = startY; y < startY + boxH; y += stride) {
    final rowOffset = y * rowStride;
    for (int x = startX; x < startX + boxW; x += stride) {
      final pixelOffset = rowOffset + x * 4; // BGRA = 4 bytes/pixel
      if (pixelOffset + 2 >= bytes.length) continue;
      final b = bytes[pixelOffset];
      final g = bytes[pixelOffset + 1];
      final r = bytes[pixelOffset + 2];
      // Standard luma approximation.
      sum += ((0.299 * r) + (0.587 * g) + (0.114 * b)).round();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}
