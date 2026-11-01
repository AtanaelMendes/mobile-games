import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import 'obstacle_match.dart';

class ObstacleGame extends FlameGame {
  ObstacleGame(this.match);
  final ObstacleMatch match;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  void update(double dt) {
    super.update(dt);
    match.update(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final scale = math.min(size.x / match.imageSize.width,
        size.y / match.imageSize.height);
    final width = match.playerCount == 1 ? size.x : match.imageSize.width * scale;
    final height = match.playerCount == 1 ? size.y : match.imageSize.height * scale;
    final left = (size.x - width) / 2;
    final top = (size.y - height) / 2;
    Offset screen(Offset p) => Offset(left + p.dx * width, top + p.dy * height);
    final paint = Paint();
    paint.color = const Color(0xCC9EA992);
    canvas.drawRect(Rect.fromLTWH(left, top, width, height), paint);
    paint
      ..color = const Color(0xFF374538)
      ..style = PaintingStyle.stroke
      ..strokeWidth = height * 0.006;
    for (var lane = 0; lane < match.playerCount; lane++) {
      final laneLeft = left + lane * width / match.playerCount;
      final laneWidth = width / match.playerCount;
      canvas.drawRect(Rect.fromLTWH(laneLeft + laneWidth * 0.035,
          top + height * 0.045, laneWidth * 0.93, height * 0.91), paint);
      for (var i = 1; i < 4; i++) {
        final x = laneLeft + laneWidth * i / 4;
        for (var y = 0.05; y < 0.95; y += 0.10) {
          final movingY = (y + match.elapsed * 0.09) % 0.95;
          canvas.drawLine(Offset(x, top + movingY * height),
              Offset(x, top + (movingY + 0.035) * height), paint);
        }
      }
    }
    paint.style = PaintingStyle.fill;
    for (final obstacle in match.obstacles) {
      final center = screen(obstacle.position);
      paint.color = obstacle.resolved && obstacle.collided
          ? const Color(0xFFCE553B) : const Color(0xFF293B31);
      final block = height * 0.036;
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 3; col++) {
          canvas.drawRect(Rect.fromCenter(
              center: center + Offset((col - 1) * block, row * block),
              width: block * 0.86, height: block * 0.86), paint);
        }
      }
    }
    for (final player in match.activePlayers) {
      final center = screen(match.avatarCenter(player));
      paint.color = match.players[player]!.active
          ? const Color(0xFF24392D) : const Color(0x7724392D);
      final unit = height * 0.025;
      void block(double x, double y, double w, double h) => canvas.drawRect(
          Rect.fromLTWH(center.dx + x * unit, center.dy + y * unit,
              w * unit, h * unit), paint);
      // Pixel car: narrow hood, windshield, cabin and four visible wheels.
      block(-1, -3, 2, 2);
      block(-1.5, -1, 3, 3);
      block(-2, 2, 4, 1);
      block(-2.2, -1.2, 0.7, 1.3);
      block(1.5, -1.2, 0.7, 1.3);
      block(-2.2, 1.4, 0.7, 1.5);
      block(1.5, 1.4, 0.7, 1.5);
      paint.color = const Color(0xFF9EA992);
      block(-0.9, -0.6, 1.8, 0.7);
    }
  }
}
