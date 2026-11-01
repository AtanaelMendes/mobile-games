import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import '../pose/pose.dart';
import 'avatar_match.dart';

class AvatarGame extends FlameGame {
  AvatarGame(this.match);
  final AvatarMatch match;

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
    Offset onScreen(Offset point) => Offset(left + point.dx * width,
        top + point.dy * height);
    final paint = Paint();

    for (final drop in match.drops) {
      final center = onScreen(drop.position);
      if (drop.hit) {
        final progress = (drop.hitTime / 0.4).clamp(0.0, 1.0);
        paint
          ..color = (drop.kind == FallingKind.bomb
              ? const Color(0xFFFF8738) : const Color(0xFFFFFFFF))
              .withValues(alpha: 1 - progress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawCircle(center, height * (0.03 + progress * 0.09), paint);
        paint.style = PaintingStyle.fill;
        continue;
      }
      if (drop.kind == FallingKind.bomb) {
        paint.color = const Color(0xFF20232F);
        canvas.drawCircle(center, height * 0.034, paint);
        paint
          ..color = const Color(0xFFFF663B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(center, height * 0.034, paint);
        paint.style = PaintingStyle.fill;
        paint.color = const Color(0xFFFFC247);
        canvas.drawCircle(center + Offset(height * 0.023, -height * 0.038),
            height * 0.010, paint);
      } else {
        paint.color = drop.player == PlayerId.player1
            ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8);
        canvas.drawCircle(center, height * 0.032, paint);
        paint.color = const Color(0xBFFFFFFF);
        canvas.drawCircle(center + Offset(-height * 0.010, -height * 0.010),
            height * 0.008, paint);
      }
    }

    for (final player in match.activePlayers) {
      final center = onScreen(match.avatarCenter(player));
      final active = match.players[player]!.active;
      final color = player == PlayerId.player1
          ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8);
      paint.color = color.withValues(alpha: active ? 1 : 0.4);
      canvas.drawCircle(center + Offset(0, -height * 0.055), height * 0.021, paint);
      final body = RRect.fromRectAndRadius(Rect.fromCenter(center: center,
          width: height * 0.064, height: height * 0.075),
          Radius.circular(height * 0.014));
      canvas.drawRRect(body, paint);
      paint
        ..strokeWidth = height * 0.012
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center + Offset(-height * 0.015, height * 0.038),
          center + Offset(-height * 0.026, height * 0.084), paint);
      canvas.drawLine(center + Offset(height * 0.015, height * 0.038),
          center + Offset(height * 0.026, height * 0.084), paint);
    }
  }
}
