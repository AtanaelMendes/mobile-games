import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/game/balloon_match.dart';
import 'package:mobile_games/game/obstacle_match.dart';
import 'package:mobile_games/pose/pose.dart';

PoseFrame frame(PlayerId player, int timestamp, double x) => PoseFrame(
  player, timestamp, {
    0: Joint(x, 0.2, 1),
    11: Joint(x - 0.1, 0.4, 1), 12: Joint(x + 0.1, 0.4, 1),
    15: Joint(x, 0.5, 1), 16: Joint(x, 0.5, 1),
    23: Joint(x - 0.05, 0.7, 1), 24: Joint(x + 0.05, 0.7, 1),
  }, 1,
);

void ready(BalloonMatch match) {
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 9; i++) {
    for (final player in match.activePlayers) {
      match.accept(frame(player, now + i * 40, 0.5));
    }
  }
}

void main() {
  test('solo mode uses the full image and needs only one tracked player', () {
    final balloons = BalloonMatch(playerCount: 1);
    ready(balloons);
    final area = balloons.players[PlayerId.player1]!
        .hitAreas(PlayerId.player1, playerCount: 1).first;
    expect(area.center, const Offset(0.5, 0.2));
    balloons.begin();
    balloons.update(0.05);
    expect(balloons.pausedForTracking, isFalse);

    final obstacle = ObstacleMatch(playerCount: 1);
    ready(obstacle);
    expect(obstacle.avatarCenter(PlayerId.player1).dx, closeTo(0.5, 0.01));
    obstacle.begin();
    expect(obstacle.remaining, 120);
    obstacle.update(0.05);
    expect(obstacle.pausedForTracking, isFalse);
  });

  test('each obstacle awards one point for a dodge or minus two for a hit', () {
    final match = ObstacleMatch(playerCount: 2);
    ready(match);
    final miss = Obstacle(1, PlayerId.player1, const Offset(0.1, 0.83), 0);
    final hit = Obstacle(2, PlayerId.player2,
        match.avatarCenter(PlayerId.player2), 0);
    expect(match.resolve(miss, PlayerId.player2, collision: false), isFalse);
    expect(match.resolve(miss, PlayerId.player1, collision: false), isTrue);
    expect(match.resolve(miss, PlayerId.player1, collision: false), isFalse);
    expect(match.resolve(hit, PlayerId.player2, collision: true), isTrue);
    expect(match.scores[PlayerId.player1], 1);
    expect(match.scores[PlayerId.player2], -2);
  });

  test('passing the avatar automatically scores a dodge or collision', () {
    final match = ObstacleMatch(playerCount: 1);
    ready(match);
    match.begin();
    match.obstacles.add(Obstacle(1, PlayerId.player1,
        const Offset(0.15, 0.819), 1));
    match.update(0.05);
    expect(match.scores[PlayerId.player1], 1);
    match.obstacles.add(Obstacle(2, PlayerId.player1,
        Offset(match.avatarCenter(PlayerId.player1).dx, 0.819), 1));
    match.update(0.05);
    expect(match.scores[PlayerId.player1], -1);
  });
}
