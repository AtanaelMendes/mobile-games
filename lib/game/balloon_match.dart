import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../pose/coordinates.dart';
import '../pose/pose.dart';

class Balloon {
  Balloon(this.id, this.player, this.position, this.speed);
  final int id;
  final PlayerId player;
  Offset position;
  final double speed;
  bool popped = false;
  double popTime = 0;
}

class HitArea {
  const HitArea(this.center, this.radius, this.previous);
  final Offset center;
  final double radius;
  final Offset? previous;
}

enum PlayerState { searching, detected, ready, outside }

class PlayerTracking {
  PoseFrame? frame;
  int lastSeenMs = 0;
  int previousTimestampMs = 0;
  final Map<int, Offset> smoothed = {};
  final Map<int, Offset> previous = {};
  double minReachY = 0.16;
  double maxReachY = 0.82;
  int samples = 0;
  double fps = 0;
  PlayerState state = PlayerState.searching;

  void accept(PoseFrame incoming) {
    if (incoming.timestampMs <= previousTimestampMs) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final oldTimestamp = previousTimestampMs;
    previousTimestampMs = incoming.timestampMs;
    frame = incoming;
    if (!incoming.detected) {
      state = PlayerState.searching;
      previous.clear();
      smoothed.clear();
      return;
    }
    final key = incoming.joint(0) ?? incoming.joint(11) ?? incoming.joint(12);
    if (key == null || key.x < 0.04 || key.x > 0.96 || key.y < 0.03 || key.y > 0.97) {
      state = PlayerState.outside;
      previous.clear();
      smoothed.clear();
      return;
    }
    state = samples >= 8 ? PlayerState.ready : PlayerState.detected;
    lastSeenMs = now;
    if (oldTimestamp > 0) {
      fps = fps == 0 ? 1000 / (incoming.timestampMs - oldTimestamp)
          : fps * 0.8 + 200 / (incoming.timestampMs - oldTimestamp);
    }
    previous
      ..clear()
      ..addAll(smoothed);
    for (final index in [0, 15, 16]) {
      final joint = incoming.joint(index);
      if (joint == null || joint.x < 0 || joint.x > 1 || joint.y < 0 || joint.y > 1) {
        smoothed.remove(index);
        previous.remove(index);
        continue;
      }
      final point = Offset(joint.x, joint.y);
      smoothed[index] = smoothed[index] == null ? point
          : Offset.lerp(smoothed[index], point, 0.65)!;
      if (index != 0) {
        minReachY = math.min(minReachY, joint.y).clamp(0.04, 0.35);
        maxReachY = math.max(maxReachY, joint.y).clamp(0.6, 0.96);
      }
    }
    samples++;
  }

  bool get active => state == PlayerState.ready &&
      DateTime.now().millisecondsSinceEpoch - lastSeenMs < 280;

  List<HitArea> hitAreas(PlayerId player, {int playerCount = 2}) {
    if (!active) return [];
    final shoulderA = frame?.joint(11);
    final shoulderB = frame?.joint(12);
    final width = shoulderA != null && shoulderB != null
        ? (shoulderA.x - shoulderB.x).abs() : 0.2;
    final handRadius = (width * 0.22).clamp(0.035, 0.09) / 2;
    final headRadius = (width * 0.32).clamp(0.05, 0.13) / 2;
    return [for (final entry in smoothed.entries)
      HitArea(playerCount == 1 ? entry.value : PoseCoordinates.localToImage(player, entry.value),
          entry.key == 0 ? headRadius : handRadius,
          previous[entry.key] == null ? null
              : playerCount == 1 ? previous[entry.key]!
                  : PoseCoordinates.localToImage(player, previous[entry.key]!))];
  }
}

class BalloonMatch extends ChangeNotifier {
  BalloonMatch({this.durationSeconds = 60, this.difficulty = 1, this.playerCount = 2});
  final int durationSeconds;
  final double difficulty;
  final int playerCount;
  Iterable<PlayerId> get activePlayers => PlayerId.values.take(playerCount);
  final players = {for (final id in PlayerId.values) id: PlayerTracking()};
  final scores = {for (final id in PlayerId.values) id: 0};
  final balloons = <Balloon>[];
  final random = math.Random();
  Size imageSize = const Size(16, 9);
  double remaining = 60;
  double elapsed = 0;
  double spawnClock = 0;
  int nextId = 0;
  bool running = false;
  bool pausedForTracking = false;
  bool finished = false;
  VoidCallback? onPop;

  void accept(PoseFrame frame) {
    imageSize = Size(frame.imageWidth.toDouble(), frame.imageHeight.toDouble());
    players[frame.player]!.accept(frame);
    if (pausedForTracking && activePlayers.every((id) => players[id]!.active)) {
      pausedForTracking = false;
    }
    notifyListeners();
  }

  void begin() {
    remaining = durationSeconds.toDouble();
    elapsed = 0;
    spawnClock = 0;
    balloons.clear();
    scores.updateAll((_, _) => 0);
    finished = false;
    pausedForTracking = false;
    running = true;
    notifyListeners();
  }

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
    final interval = (1.5 / difficulty - elapsed * 0.006).clamp(0.5, 1.8);
    if (spawnClock >= interval) {
      spawnClock = 0;
      for (final player in activePlayers) {
        final tracking = players[player]!;
        final laneWidth = 1.0 / playerCount;
        final x = player.index * laneWidth + laneWidth * (0.16 + random.nextDouble() * 0.68);
        final startY = tracking.minReachY.clamp(0.05, 0.30) - 0.08;
        balloons.add(Balloon(nextId++, player, Offset(x, startY),
            (0.10 + elapsed * 0.0018) * difficulty));
      }
    }
    for (final balloon in balloons) {
      if (balloon.popped) {
        balloon.popTime += dt;
        continue;
      }
      balloon.position += Offset(0, balloon.speed * dt);
      for (final hit in players[balloon.player]!.hitAreas(balloon.player,
          playerCount: playerCount)) {
        if (_distanceToSegment(balloon.position, hit.previous ?? hit.center,
                hit.center) < hit.radius + 0.022) {
          pop(balloon, balloon.player);
          break;
        }
      }
    }
    balloons.removeWhere((b) => b.position.dy > 1.05 || b.popTime > 0.35);
    notifyListeners();
  }

  bool pop(Balloon balloon, PlayerId player) {
    if (balloon.popped || balloon.player != player || !players[player]!.active) return false;
    balloon.popped = true;
    scores[player] = scores[player]! + 1;
    onPop?.call();
    notifyListeners();
    return true;
  }

  String get winner {
    if (playerCount == 1) return 'Fim de partida!';
    final left = scores[PlayerId.player1]!;
    final right = scores[PlayerId.player2]!;
    return left == right ? 'Empate!' : left > right ? 'Jogador 1 venceu!' : 'Jogador 2 venceu!';
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) /
            lengthSquared).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}
