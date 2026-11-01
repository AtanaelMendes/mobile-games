import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/game/avatar_match.dart';
import 'package:mobile_games/pose/pose.dart';

PoseFrame bodyPose(PlayerId player, int timestamp, double x,
    {bool visible = true}) => PoseFrame(player, timestamp, visible ? {
      0: Joint(x, 0.2, 1),
      11: Joint(x - 0.10, 0.44, 1),
      12: Joint(x + 0.10, 0.44, 1),
      23: Joint(x - 0.06, 0.74, 1),
      24: Joint(x + 0.06, 0.74, 1),
    } : {}, 1);

AvatarMatch readyMatch() {
  final match = AvatarMatch();
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 9; i++) {
    match.accept(bodyPose(PlayerId.player1, now + i * 40, 0.2));
    match.accept(bodyPose(PlayerId.player2, now + i * 40, 0.8));
  }
  return match;
}

void main() {
  test('body movement steers each avatar only inside its half', () {
    final match = readyMatch();
    expect(match.avatarCenter(PlayerId.player1).dx, lessThan(0.25));
    expect(match.avatarCenter(PlayerId.player2).dx, greaterThan(0.75));
    final now = DateTime.now().millisecondsSinceEpoch + 1000;
    match.accept(bodyPose(PlayerId.player1, now, 0.95));
    expect(match.avatarCenter(PlayerId.player1).dx, lessThan(0.5));
  });

  test('balloon and bomb score once for the correct player', () {
    final match = readyMatch();
    final balloon = FallingItem(1, PlayerId.player1, FallingKind.balloon,
        const Offset(0.1, 0.83), 0);
    final bomb = FallingItem(2, PlayerId.player1, FallingKind.bomb,
        const Offset(0.1, 0.83), 0);
    expect(match.collect(balloon, PlayerId.player2), isFalse);
    expect(match.collect(balloon, PlayerId.player1), isTrue);
    expect(match.collect(balloon, PlayerId.player1), isFalse);
    expect(match.collect(bomb, PlayerId.player1), isTrue);
    expect(match.collect(bomb, PlayerId.player1), isFalse);
    expect(match.scores[PlayerId.player1], -2);
    expect(match.scores[PlayerId.player2], 0);
  });

  test('falling object hits avatar, then tracking loss disables hits', () {
    final match = readyMatch();
    match.begin();
    final center = match.avatarCenter(PlayerId.player1);
    match.drops.add(FallingItem(1, PlayerId.player1, FallingKind.balloon,
        center, 0));
    match.update(0.01);
    expect(match.scores[PlayerId.player1], 1);

    final now = DateTime.now().millisecondsSinceEpoch + 1000;
    match.accept(bodyPose(PlayerId.player1, now, 0.2, visible: false));
    match.drops.add(FallingItem(2, PlayerId.player1, FallingKind.bomb,
        center, 0));
    match.update(0.01);
    expect(match.scores[PlayerId.player1], 1);
  });

  test('rain becomes faster and more frequent over time', () {
    final match = AvatarMatch();
    final speed = match.fallingSpeed;
    final interval = match.spawnInterval;
    match.elapsed = 45;
    expect(match.fallingSpeed, greaterThan(speed));
    expect(match.spawnInterval, lessThan(interval));
  });
}
