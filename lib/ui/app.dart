import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/balloon_game.dart';
import '../game/balloon_match.dart';
import '../game/avatar_game.dart';
import '../game/avatar_match.dart';
import '../game/obstacle_game.dart';
import '../game/obstacle_match.dart';
import '../pose/pose.dart';

class MobileGamesApp extends StatelessWidget {
  const MobileGamesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mobile Games', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF111827),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF58D5FF),
          brightness: Brightness.dark),
    ),
    home: const HomeScreen(),
  );
}

class GameSettings {
  bool simulated = false;
  String? cameraId;
  double zoom = 1;
  bool mirror = false;
  bool sound = true;
  bool debug = false;
  double difficulty = 1;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final settings = GameSettings();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.sports_esports, size: 54, color: Color(0xFF58D5FF)),
        const Text('MOBILE GAMES', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        const Text('Uma câmera, muito movimento.'),
        const SizedBox(height: 30),
        FilledButton.icon(onPressed: () => _choosePlayers(GameMode.balloons),
          icon: const Icon(Icons.circle_outlined), label: const Text('Balões')),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () => _choosePlayers(GameMode.avatar),
          icon: const Icon(Icons.person), label: const Text('Avatar · Balões e bombas')),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () => _choosePlayers(GameMode.obstacles),
          icon: const Icon(Icons.grid_view), label: const Text('Desvio de obstáculos')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => _settings(context),
          icon: const Icon(Icons.settings), label: const Text('Configurações')),
      ]),
    )),
  );

  Future<void> _choosePlayers(GameMode mode) async {
    final count = await showDialog<int>(context: context, builder: (context) =>
      AlertDialog(title: const Text('Como quer jogar?'), content: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.person), title: const Text('1 jogador'),
            subtitle: const Text('Usar a tela inteira'),
            onTap: () => Navigator.pop(context, 1)),
          ListTile(leading: const Icon(Icons.people), title: const Text('2 jogadores'),
            subtitle: const Text('Uma metade para cada jogador'),
            onTap: () => Navigator.pop(context, 2)),
        ])));
    if (count == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
      PlayScreen(settings: settings, mode: mode, playerCount: count)));
  }

  void _settings(BuildContext context) => showDialog<void>(context: context,
    builder: (context) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: const Text('Configurações'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(title: const Text('Modo simulado'),
            subtitle: const Text('Movimentos artificiais, sem rastreamento real'),
            value: settings.simulated, onChanged: (v) => refresh(() => settings.simulated = v)),
          const Text('Câmera e zoom podem ser escolhidos na preparação.'),
          SwitchListTile(title: const Text('Espelhar imagem'), value: settings.mirror,
            onChanged: (v) => refresh(() => settings.mirror = v)),
          SwitchListTile(title: const Text('Som'), value: settings.sound,
            onChanged: (v) => refresh(() => settings.sound = v)),
          SwitchListTile(title: const Text('Depuração'), value: settings.debug,
            onChanged: (v) => refresh(() => settings.debug = v)),
          const Text('Dificuldade'),
          Slider(value: settings.difficulty, min: 0.7, max: 1.5, divisions: 8,
            label: settings.difficulty.toStringAsFixed(1),
            onChanged: (v) => refresh(() => settings.difficulty = v)),
          const Text('Para mostrar na TV, ative o espelhamento nas configurações do Android.'),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    )));
}

enum PlayStage { preparation, calibration, match, result }
enum GameMode { balloons, avatar, obstacles }

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.settings, required this.mode,
    required this.playerCount});
  final GameSettings settings;
  final GameMode mode;
  final int playerCount;
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  late final PoseSource source;
  late final BalloonMatch match;
  late final FlameGame game;
  StreamSubscription<PoseFrame>? subscription;
  StreamSubscription<String>? statusSubscription;
  String? cameraStatus;
  PlayStage stage = PlayStage.preparation;
  String? error;
  bool starting = false;
  Timer? refreshTimer;
  static const methods = MethodChannel('mobile_games/camera');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    source = widget.settings.simulated
        ? SimulatedPoseSource(playerCount: widget.playerCount) : NativePoseSource();
    match = switch (widget.mode) {
      GameMode.avatar => AvatarMatch(difficulty: widget.settings.difficulty,
          playerCount: widget.playerCount),
      GameMode.obstacles => ObstacleMatch(difficulty: widget.settings.difficulty,
          playerCount: widget.playerCount),
      GameMode.balloons => BalloonMatch(difficulty: widget.settings.difficulty,
          playerCount: widget.playerCount),
    };
    game = switch (widget.mode) {
      GameMode.avatar => AvatarGame(match as AvatarMatch),
      GameMode.obstacles => ObstacleGame(match as ObstacleMatch),
      GameMode.balloons => BalloonGame(match),
    };
    match.onPop = () {
      if (widget.settings.sound && !source.simulated) {
        methods.invokeMethod<void>('playPop');
      }
    };
    if (match is AvatarMatch) {
      (match as AvatarMatch).onBomb = () {
        if (widget.settings.sound && !source.simulated) {
          methods.invokeMethod<void>('playBomb');
        }
      };
    }
    if (match is ObstacleMatch) {
      (match as ObstacleMatch).onCollision = () {
        if (widget.settings.sound && !source.simulated) {
          methods.invokeMethod<void>('playBomb');
        }
      };
    }
    match.addListener(_refresh);
    refreshTimer = Timer.periodic(const Duration(milliseconds: 150), (_) => _refresh());
    _start();
  }

  Future<void> _start() async {
    if (starting) return;
    starting = true;
    try {
      if (!source.simulated) {
        await methods.invokeMethod<void>('configure', {
          'front': false, 'mirror': widget.settings.mirror,
          'cameraId': widget.settings.cameraId, 'zoom': widget.settings.zoom,
          'playerCount': widget.playerCount,
        });
      }
      statusSubscription ??= source.statuses.listen((status) {
        if (mounted) setState(() => cameraStatus = status);
      });
      subscription ??= source.frames.listen(match.accept, onError: (Object e) {
        if (mounted) setState(() => error = e.toString());
      });
      await source.start();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      starting = false;
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (stage == PlayStage.match && match.finished) stage = PlayStage.result;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      source.stop();
      match.pausedForTracking = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    subscription?.cancel();
    statusSubscription?.cancel();
    source.stop();
    source.dispose();
    match.removeListener(_refresh);
    match.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p1 = match.players[PlayerId.player1]!;
    final p2 = match.players[PlayerId.player2]!;
    return Scaffold(body: Stack(children: [
      Positioned.fill(child: source.simulated
          ? const ColoredBox(color: Color(0xFF243445))
          : const AndroidView(viewType: 'mobile_games/camera_view')),
      if (widget.mode != GameMode.balloons)
        const Positioned.fill(child: ColoredBox(color: Color(0xFF243445))),
      Positioned.fill(child: IgnorePointer(child: GameWidget(game: game,
          backgroundBuilder: (_) => const SizedBox.expand()))),
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(
          match, widget.settings.debug)))),
      Positioned(left: 14, top: 12, child: _score(1, p1, PlayerId.player1)),
      if (widget.playerCount == 2)
        Positioned(right: 14, top: 12, child: _score(2, p2, PlayerId.player2)),
      Positioned(top: 12, left: 0, right: 0, child: Center(child: Chip(
          label: Text(stage == PlayStage.match ? '${match.remaining.ceil()} s' : 'Mobile Games')))),
      if (source.simulated) const Positioned(left: 12, bottom: 10,
          child: Chip(label: Text('MODO SIMULADO · sem câmera real'))),
      if (cameraStatus != null && !source.simulated) Positioned(left: 170,
        right: 170, top: 130, child: Center(child: Chip(label: Text(cameraStatus!)))),
      if (!source.simulated && (stage == PlayStage.preparation ||
          stage == PlayStage.calibration)) Positioned(top: 65, left: 0, right: 0,
        child: Center(child: OutlinedButton.icon(onPressed: _openCameraPicker,
          icon: const Icon(Icons.camera_alt), label: const Text('Escolher câmera e zoom')))),
      Positioned(left: 0, right: 0, bottom: 14, child: Center(child: _stagePanel(p1, p2))),
      Positioned(left: 8, top: 80, child: IconButton.filledTonal(
        tooltip: 'Voltar', onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back))),
      if (error != null) Center(child: Card(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Câmera indisponível ou permissão negada'), Text(error!),
          FilledButton(onPressed: _start, child: const Text('Tentar novamente')),
        ])))),
    ]));
  }

  Widget _score(int number, PlayerTracking tracking, PlayerId id) =>
      Column(crossAxisAlignment: number == 1 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [Text('JOGADOR $number · ${match.scores[id]}', style: TextStyle(
          color: number == 1 ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8),
          fontSize: 19, fontWeight: FontWeight.bold)),
          Text(_stateLabel(tracking)),
          if (widget.settings.debug) Text('${tracking.fps.toStringAsFixed(1)} fps · '
              '${tracking.frame?.processingMs.toStringAsFixed(0) ?? '-'} ms · '
              '${DateTime.now().millisecondsSinceEpoch - tracking.lastSeenMs} ms idade · '
              '${tracking.frame?.imageWidth ?? '-'}×${tracking.frame?.imageHeight ?? '-'}'),
        ]);

  Future<void> _openCameraPicker() async {
    try {
      final raw = await methods.invokeListMethod<Map<dynamic, dynamic>>('listCameras');
      if (!mounted) return;
      final options = (raw ?? []).map((data) => _CameraOption(
        data['id'] as String, data['facing'] as String,
        (data['field'] as num).toDouble(), (data['minZoom'] as num).toDouble(),
        (data['maxZoom'] as num).toDouble(), data['usable'] as bool,
      )).toList();
      if (options.isEmpty) throw StateError('Nenhuma câmera disponível');
      var selectedId = widget.settings.cameraId ?? options.firstWhere(
        (c) => c.usable && c.facing == 'back',
        orElse: () => options.first,
      ).id;
      var zoom = widget.settings.zoom;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) =>
        StatefulBuilder(builder: (dialogContext, refresh) {
          final chosen = options.firstWhere((c) => c.id == selectedId);
          return AlertDialog(title: Text('Câmera e zoom · ${options.length} detectadas'),
            content: SizedBox(width: 540, height: 460,
              child: Column(children: [
                const Text('Câmeras expostas ao aplicativo pelo Android. A lente 0,6× pode não aparecer nesta lista.'),
                const SizedBox(height: 8),
                Expanded(child: ListView(children: [for (final camera in options)
                  ListTile(
                    dense: true,
                    enabled: camera.usable,
                    selected: camera.id == selectedId,
                    leading: Icon(camera.facing == 'front' ? Icons.camera_front : Icons.camera_rear),
                    title: Text('${camera.facing == 'front' ? 'Frontal' : 'Traseira'} · ID ${camera.id}'),
                    subtitle: Text('Ângulo horizontal ~${camera.angle.round()}° · zoom ${camera.minZoom.toStringAsFixed(1)}×–${camera.maxZoom.toStringAsFixed(1)}×${camera.usable ? '' : ' · indisponível para o jogo'}'),
                    trailing: camera.id == selectedId ? const Icon(Icons.check_circle) : null,
                    onTap: !camera.usable ? null : () async {
                      refresh(() {
                        selectedId = camera.id;
                        zoom = 1.0.clamp(camera.minZoom, camera.maxZoom);
                      });
                      widget.settings.cameraId = camera.id;
                      widget.settings.zoom = zoom;
                      await methods.invokeMethod<void>('configure', {
                        'front': camera.facing == 'front',
                        'mirror': widget.settings.mirror,
                        'cameraId': camera.id, 'zoom': zoom,
                        'playerCount': widget.playerCount,
                      });
                    },
                  ),
                ])),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Zoom: ${zoom.toStringAsFixed(1)}×'),
                  const SizedBox(width: 12),
                  TextButton(onPressed: !chosen.usable ? null : () async {
                    final actual = await methods.invokeMethod<double>('setZoom', {'zoom': 1.0});
                    if (actual != null) {
                      widget.settings.zoom = actual;
                      refresh(() => zoom = actual);
                    }
                  }, child: const Text('Voltar a 1×')),
                ]),
                Slider(value: zoom.clamp(chosen.minZoom, chosen.maxZoom),
                  min: chosen.minZoom, max: chosen.maxZoom,
                  onChanged: chosen.usable ? (value) => refresh(() => zoom = value) : null,
                  onChangeEnd: chosen.usable ? (value) async {
                    final actual = await methods.invokeMethod<double>('setZoom', {'zoom': value});
                    if (actual != null) {
                      widget.settings.zoom = actual;
                      refresh(() => zoom = actual);
                    }
                  } : null),
              ])),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'))],
          );
        }));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao listar câmeras: $e')));
    }
  }

  String _stateLabel(PlayerTracking p) {
    if (p.state == PlayerState.outside) { return 'Fora da área · volte à sua metade'; }
    if (p.frame == null || !p.frame!.detected ||
        DateTime.now().millisecondsSinceEpoch - p.lastSeenMs > 300) { return 'Procurando'; }
    return p.state == PlayerState.ready ? 'Pronto' : 'Detectado';
  }

  Widget _stagePanel(PlayerTracking p1, PlayerTracking p2) {
    final avatarMode = widget.mode == GameMode.avatar;
    final obstacleMode = widget.mode == GameMode.obstacles;
    final solo = widget.playerCount == 1;
    if (stage == PlayStage.preparation) { return _panel(
      obstacleMode ? 'Desvie dos blocos movendo o corpo para os lados.'
          : avatarMode ? 'Movimente o corpo para os lados e controle seu boneco.'
          : solo ? 'Fique diante da câmera, com corpo e mãos visíveis.'
          : 'Fique em sua metade, com corpo e mãos visíveis.',
      obstacleMode ? 'Partida de 2 minutos. Desvio: +1. Colisão: -2.'
          : avatarMode ? 'Pegue balões e desvie das bombas (-3).'
          : solo ? 'Você pode se mover por toda a tela.'
          : 'Uma pessoa em cada região. Mantenha distância da linha central.',
      'Calibrar', () => setState(() => stage = PlayStage.calibration)); }
    if (stage == PlayStage.calibration) { return _panel(
      'Calibração', avatarMode || obstacleMode
          ? solo ? 'Mova o corpo para a esquerda e direita por toda a tela.'
              : 'Movam o corpo para os lados dentro da própria metade.'
          : solo ? 'Erga e mova as mãos para marcar seu alcance.'
              : 'Ergam e movam as mãos para marcar o alcance de cada jogador.',
      'Começar partida', p1.state == PlayerState.ready &&
          (solo || p2.state == PlayerState.ready)
          ? () { match.begin(); setState(() => stage = PlayStage.match); } : null); }
    if (stage == PlayStage.result) { return _panel(match.winner,
      solo ? 'Pontuação: ${match.scores[PlayerId.player1]}'
          : 'Jogador 1: ${match.scores[PlayerId.player1]} · Jogador 2: ${match.scores[PlayerId.player2]}',
      'Jogar novamente', () => setState(() => stage = PlayStage.calibration)); }
    if (match.pausedForTracking) { return _panel('Partida pausada',
        solo ? 'Reposicione-se diante da câmera para continuar.'
            : 'Reposicionem-se nas próprias regiões para continuar.',
        solo ? 'Aguardando jogador' : 'Aguardando jogadores', null); }
    return const SizedBox.shrink();
  }

  Widget _panel(String title, String detail, String action, VoidCallback? onPressed) =>
      Card(color: const Color(0xDD111827), child: Padding(padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          Text(detail), const SizedBox(height: 7),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ])));
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.match, this.debug);
  final BalloonMatch match;
  final bool debug;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / match.imageSize.width,
        size.height / match.imageSize.height);
    final imageHeight = match.playerCount == 1 ? size.height : match.imageSize.height * scale;
    final top = (size.height - imageHeight) / 2;
    if (match.playerCount == 2) {
      canvas.drawLine(Offset(size.width / 2, top), Offset(size.width / 2, top + imageHeight),
        Paint()..color = const Color(0xBBFFFFFF)..strokeWidth = 2);
    }
    if (!debug) return;
    for (final id in match.activePlayers) {
      final tracking = match.players[id]!;
      for (final point in tracking.smoothed.values) {
        final imageWidth = match.playerCount == 1 ? size.width : match.imageSize.width * scale;
        canvas.drawCircle(Offset((size.width - imageWidth) / 2 +
            (point.dx + id.index) * imageWidth / match.playerCount,
            top + point.dy * imageHeight), 5, Paint()..color = id.index == 0
                ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) => true;
}

class _CameraOption {
  const _CameraOption(this.id, this.facing, this.field, this.minZoom,
      this.maxZoom, this.usable);
  final String id;
  final String facing;
  final double field;
  final double minZoom;
  final double maxZoom;
  final bool usable;
  double get angle => 2 * math.atan(field / 2) * 180 / math.pi;
}
