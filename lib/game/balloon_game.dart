import 'dart:ui';
import 'dart:math' as math;

import 'package:flame/game.dart';

import 'balloon_match.dart';

class BalloonGame extends FlameGame {
  BalloonGame(this.match);
  final BalloonMatch match;

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
    final w = size.x;
    final h = size.y;
    final scale = math.min(w / match.imageSize.width, h / match.imageSize.height);
    final displayW = match.playerCount == 1 ? w : match.imageSize.width * scale;
    final displayH = match.playerCount == 1 ? h : match.imageSize.height * scale;
    final left = (w - displayW) / 2;
    final top = (h - displayH) / 2;
    final paint = Paint();
    for (final balloon in match.balloons) {
      final center = Offset(left + balloon.position.dx * displayW,
          top + balloon.position.dy * displayH);
      final radius = displayH * (balloon.popped ? 0.045 + balloon.popTime * 0.09 : 0.045);
      final base = balloon.player.index == 0
          ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8);
      paint.color = base.withValues(alpha: balloon.popped
          ? (1 - balloon.popTime / 0.35).clamp(0, 1) : 0.92);
      canvas.drawCircle(center, radius, paint);
      if (!balloon.popped) {
        paint.color = const Color(0xAAFFFFFF);
        canvas.drawCircle(center + Offset(-radius * 0.3, -radius * 0.3),
            radius * 0.2, paint);
        paint
          ..color = base
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(center + Offset(0, radius),
            center + Offset(0, radius * 1.7), paint);
        paint.style = PaintingStyle.fill;
      }
    }
  }
}
