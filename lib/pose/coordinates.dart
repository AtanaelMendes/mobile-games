import 'dart:math' as math;
import 'dart:ui';

import 'pose.dart';

/// Coordinates refer to the displayed, oriented and mirrored image.
/// Native inference crops it into two equal vertical regions.
class PoseCoordinates {
  static Offset localToImage(PlayerId player, Offset local) => Offset(
      (local.dx + (player == PlayerId.player2 ? 1 : 0)) / 2, local.dy);

  static Offset imageToGame(Offset image, Size imageSize, Size gameSize) {
    final scale = math.min(gameSize.width / imageSize.width,
        gameSize.height / imageSize.height);
    return Offset((gameSize.width - imageSize.width * scale) / 2 + image.dx * imageSize.width * scale,
        (gameSize.height - imageSize.height * scale) / 2 + image.dy * imageSize.height * scale);
  }

  static Offset localToGame(PlayerId player, Offset local, Size imageSize,
          Size gameSize) =>
      imageToGame(localToImage(player, local), imageSize, gameSize);

  static Offset orient(Offset raw, int clockwiseDegrees, {bool mirror = false}) {
    final point = switch (clockwiseDegrees % 360) {
      90 => Offset(1 - raw.dy, raw.dx),
      180 => Offset(1 - raw.dx, 1 - raw.dy),
      270 => Offset(raw.dy, 1 - raw.dx),
      _ => raw,
    };
    return mirror ? Offset(1 - point.dx, point.dy) : point;
  }
}
