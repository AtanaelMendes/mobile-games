import 'dart:math' as math;
import 'dart:ui';

import '../pose/pose.dart';
import 'avatar_match.dart';

class Obstacle {
  Obstacle(this.id, this.player, this.position, this.speed);
  final int id;
  final PlayerId player;
  Offset position;
  final double speed;
  bool resolved = false;
  bool collided = false;
  double resolvedTime = 0;
}

class ObstacleMatch extends AvatarMatch {
  ObstacleMatch({super.difficulty, super.playerCount, math.Random? random})
      : _random = random ?? math.Random(), super(durationSeconds: 120);

  final math.Random _random;
  final obstacles = <Obstacle>[];
  int _nextObstacleId = 0;
  VoidCallback? onCollision;

  double get obstacleSpeed => (0.17 + elapsed * 0.0009) * difficulty;
  double get obstacleInterval =>
      ((1.45 - elapsed * 0.0035) / difficulty).clamp(0.68, 2.0);

  @override
  void begin() {
    super.begin();
    obstacles.clear();
    _nextObstacleId = 0;
  }

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
    if (spawnClock >= obstacleInterval) {
      spawnClock = 0;
      for (final player in activePlayers) {
        obstacles.add(Obstacle(_nextObstacleId++, player,
            Offset((player.index + 0.12 + _random.nextDouble() * 0.76) /
                playerCount, -0.06), obstacleSpeed));
      }
    }
    for (final obstacle in obstacles) {
      if (obstacle.resolved) {
        obstacle.resolvedTime += dt;
        continue;
      }
      obstacle.position += Offset(0, obstacle.speed * dt);
      if (obstacle.position.dy < 0.82 || !players[obstacle.player]!.active) {
        continue;
      }
      final avatar = avatarCenter(obstacle.player);
      final dx = (obstacle.position.dx - avatar.dx) *
          imageSize.width / imageSize.height;
      resolve(obstacle, obstacle.player, collision: dx.abs() < 0.085);
    }
    obstacles.removeWhere((o) => o.position.dy > 1.08 || o.resolvedTime > 0.5);
    notifyListeners();
  }

  bool resolve(Obstacle obstacle, PlayerId player, {required bool collision}) {
    if (obstacle.resolved || obstacle.player != player ||
        !players[player]!.active) {
      return false;
    }
    obstacle.resolved = true;
    obstacle.collided = collision;
    scores[player] = scores[player]! + (collision ? -2 : 1);
    if (collision) {
      onCollision?.call();
    }
    notifyListeners();
    return true;
  }
}
