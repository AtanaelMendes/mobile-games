import 'dart:math' as math;
import 'dart:ui';

import '../pose/pose.dart';
import 'balloon_match.dart';

enum FallingKind { balloon, bomb }

class FallingItem {
  FallingItem(this.id, this.player, this.kind, this.position, this.speed);
  final int id;
  final PlayerId player;
  final FallingKind kind;
  Offset position;
  final double speed;
  bool hit = false;
  double hitTime = 0;
}

/// A second BalloonMatch rule set: body position steers an avatar in each lane.
class AvatarMatch extends BalloonMatch {
  AvatarMatch({super.durationSeconds, super.difficulty, super.playerCount,
      math.Random? random})
      : _random = random ?? math.Random();

  final math.Random _random;
  final drops = <FallingItem>[];
  final avatarLocalX = {for (final id in PlayerId.values) id: 0.5};
  int _nextDropId = 0;
  VoidCallback? onBomb;

  @override
  void accept(PoseFrame frame) {
    super.accept(frame);
    if (!players[frame.player]!.active) return;
    final leftHip = frame.joint(23);
    final rightHip = frame.joint(24);
    final leftShoulder = frame.joint(11);
    final rightShoulder = frame.joint(12);
    final bodyX = leftHip != null && rightHip != null
        ? (leftHip.x + rightHip.x) / 2
        : leftShoulder != null && rightShoulder != null
            ? (leftShoulder.x + rightShoulder.x) / 2
            : frame.joint(0)?.x;
    if (bodyX == null) return;
    final previous = avatarLocalX[frame.player]!;
    avatarLocalX[frame.player] = (previous * 0.35 + bodyX * 0.65)
        .clamp(0.09, 0.91);
    notifyListeners();
  }

  Offset avatarCenter(PlayerId player) => Offset(
      (player.index + avatarLocalX[player]!) / playerCount, 0.83);

  @override
  void begin() {
    super.begin();
    drops.clear();
    _nextDropId = 0;
  }

  double get spawnInterval =>
      ((1.25 - elapsed * 0.008) / difficulty).clamp(0.42, 1.8);

  double get fallingSpeed =>
      (0.12 + elapsed * 0.003) * difficulty;

  @override
  void update(double dt) {
    if (!running || finished) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (activePlayers.any((id) => now - players[id]!.lastSeenMs > 1500)) {
      pausedForTracking = true;
    }
    if (pausedForTracking) return;
    dt = dt.clamp(0, 0.05);
    remaining -= dt;
    elapsed += dt;
    if (remaining <= 0) {
      remaining = 0;
      finished = true;
      running = false;
      notifyListeners();
      return;
    }
    spawnClock += dt;
    if (spawnClock >= spawnInterval) {
      spawnClock = 0;
      for (final player in activePlayers) {
        drops.add(FallingItem(_nextDropId++, player,
            _random.nextDouble() < 0.18 ? FallingKind.bomb : FallingKind.balloon,
            Offset((player.index + 0.14 + _random.nextDouble() * 0.72) / playerCount,
                -0.05), fallingSpeed));
      }
    }
    for (final drop in drops) {
      if (drop.hit) {
        drop.hitTime += dt;
        continue;
      }
      drop.position += Offset(0, drop.speed * dt);
      if (!players[drop.player]!.active) continue;
      final avatar = avatarCenter(drop.player);
      final aspect = imageSize.width / imageSize.height;
      final dx = (drop.position.dx - avatar.dx) * aspect;
      final dy = drop.position.dy - avatar.dy;
      if (math.sqrt(dx * dx + dy * dy) < 0.077) {
        collect(drop, drop.player);
      }
    }
    drops.removeWhere((drop) => drop.position.dy > 1.08 || drop.hitTime > 0.4);
    notifyListeners();
  }

  bool collect(FallingItem drop, PlayerId player) {
    if (drop.hit || drop.player != player || !players[player]!.active) return false;
    drop.hit = true;
    scores[player] = scores[player]! + (drop.kind == FallingKind.bomb ? -3 : 1);
    if (drop.kind == FallingKind.bomb) {
      onBomb?.call();
    } else {
      onPop?.call();
    }
    notifyListeners();
    return true;
  }
}
