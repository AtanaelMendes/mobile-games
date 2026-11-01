import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

enum PlayerId { player1, player2 }

class Joint {
  const Joint(this.x, this.y, this.confidence);
  final double x;
  final double y;
  final double confidence;
}

class PoseFrame {
  const PoseFrame(this.player, this.timestampMs, this.joints, this.processingMs,
      {this.imageWidth = 16, this.imageHeight = 9});
  final PlayerId player;
  final int timestampMs;
  final Map<int, Joint> joints;
  final double processingMs;
  final int imageWidth;
  final int imageHeight;
  bool get detected => joints.isNotEmpty;

  Joint? joint(int index, {double threshold = 0.55}) {
    final j = joints[index];
    return j != null && j.confidence >= threshold ? j : null;
  }
}

abstract class PoseSource {
  Stream<PoseFrame> get frames;
  bool get simulated;
  Future<void> start();
  Future<void> stop();
  void dispose();
}

class NativePoseSource implements PoseSource {
  static const _events = EventChannel('mobile_games/poses');
  static const _methods = MethodChannel('mobile_games/camera');
  final _controller = StreamController<PoseFrame>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  @override
  bool get simulated => false;
  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {
    _subscription ??= _events.receiveBroadcastStream().listen((raw) {
      final data = Map<Object?, Object?>.from(raw as Map);
      final player = data['player'] == 'player1' ? PlayerId.player1 : PlayerId.player2;
      final joints = <int, Joint>{};
      final values = Map<Object?, Object?>.from(data['joints'] as Map);
      for (final entry in values.entries) {
        final point = List<num>.from(entry.value as List);
        joints[int.parse(entry.key.toString())] = Joint(
          point[0].toDouble(), point[1].toDouble(), point[2].toDouble(),
        );
      }
      _controller.add(PoseFrame(player, (data['timestampMs'] as num).toInt(),
          joints, (data['processingMs'] as num).toDouble(),
          imageWidth: (data['width'] as num).toInt(),
          imageHeight: (data['height'] as num).toInt()));
    }, onError: _controller.addError);
    await _methods.invokeMethod<void>('start');
  }

  @override
  Future<void> stop() async {
    await _methods.invokeMethod<void>('stop');
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

class SimulatedPoseSource implements PoseSource {
  final _controller = StreamController<PoseFrame>.broadcast();
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  @override
  bool get simulated => true;
  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {
    _clock.start();
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      final t = _clock.elapsedMilliseconds;
      for (final player in PlayerId.values) {
        final phase = t / 420.0 + (player == PlayerId.player1 ? 0 : 2);
        final cx = 0.5 + 0.27 * math.sin(phase);
        final handY = 0.42 + 0.29 * math.cos(phase * 0.7);
        final joints = <int, Joint>{
          0: const Joint(0.5, 0.20, 1),
          11: const Joint(0.37, 0.44, 1), 12: const Joint(0.63, 0.44, 1),
          15: Joint(cx, handY, 1), 16: Joint(1 - cx, handY, 1),
          23: const Joint(0.43, 0.76, 1), 24: const Joint(0.57, 0.76, 1),
        };
        _controller.add(PoseFrame(player, DateTime.now().millisecondsSinceEpoch,
            joints, 0));
      }
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
