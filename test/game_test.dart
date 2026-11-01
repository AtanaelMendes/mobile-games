import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/game/balloon_match.dart';
import 'package:mobile_games/pose/coordinates.dart';
import 'package:mobile_games/pose/pose.dart';

PoseFrame pose(PlayerId id, int timestamp, {bool detected = true}) => PoseFrame(
  id, timestamp, detected ? {
    0: const Joint(0.5, 0.2, 1),
    11: const Joint(0.35, 0.4, 1),
    12: const Joint(0.65, 0.4, 1),
    15: const Joint(0.5, 0.5, 1),
    16: const Joint(0.5, 0.5, 1),
  } : {}, 1,
);

void main() {
  test('left and right local points map to independent image halves', () {
    expect(PoseCoordinates.localToImage(PlayerId.player1, const Offset(0.5, 0.3)),
        const Offset(0.25, 0.3));
    expect(PoseCoordinates.localToImage(PlayerId.player2, const Offset(0.5, 0.3)),
        const Offset(0.75, 0.3));
    expect(PoseCoordinates.localToGame(PlayerId.player2, const Offset(0.5, 0.5),
        const Size(4, 3), const Size(16, 9)), const Offset(11, 4.5));
  });

  test('rotation and mirroring use a single transform', () {
    expect(PoseCoordinates.orient(const Offset(0.2, 0.3), 90),
        const Offset(0.7, 0.2));
    final mirrored = PoseCoordinates.orient(const Offset(0.2, 0.3), 90,
        mirror: true);
    expect(mirrored.dx, closeTo(0.3, 1e-10));
    expect(mirrored.dy, closeTo(0.2, 1e-10));
    final rotated = PoseCoordinates.orient(const Offset(0.2, 0.3), 180);
    expect(rotated.dx, closeTo(0.8, 1e-10));
    expect(rotated.dy, closeTo(0.7, 1e-10));
  });

  test('a balloon scores once only for its own player', () {
    final game = BalloonMatch();
    final start = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 9; i++) {
      game.accept(pose(PlayerId.player1, start + i * 50));
      game.accept(pose(PlayerId.player2, start + i * 50));
    }
    final balloon = Balloon(1, PlayerId.player1, const Offset(0.25, 0.5), 0.1);
    expect(game.pop(balloon, PlayerId.player2), isFalse);
    expect(game.pop(balloon, PlayerId.player1), isTrue);
    expect(game.pop(balloon, PlayerId.player1), isFalse);
    expect(game.scores[PlayerId.player1], 1);
    expect(game.scores[PlayerId.player2], 0);
  });

  test('tracking loss disables collisions and clears previous trajectory', () {
    final tracking = PlayerTracking();
    final start = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 9; i++) {
      tracking.accept(pose(PlayerId.player1, start + i * 50));
    }
    expect(tracking.hitAreas(PlayerId.player1), isNotEmpty);
    tracking.accept(pose(PlayerId.player1, start + 500, detected: false));
    expect(tracking.hitAreas(PlayerId.player1), isEmpty);
    expect(tracking.previous, isEmpty);
  });
}
