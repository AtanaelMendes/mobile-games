import 'dart:async';

import 'package:audioplayers/audioplayers.dart' hide PlayerState;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/balloon_game.dart';
import '../game/balloon_match.dart';
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
  bool frontCamera = true;
  bool mirror = true;
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
        const Text('Dois jogadores, uma câmera, muito movimento.'),
        const SizedBox(height: 30),
        FilledButton.icon(onPressed: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => PlayScreen(settings: settings))),
          icon: const Icon(Icons.circle_outlined), label: const Text('Balões')),
        const SizedBox(height: 10),
        const OutlinedButton(onPressed: null, child: Text('Corrida · Em breve')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => _settings(context),
          icon: const Icon(Icons.settings), label: const Text('Configurações')),
      ]),
    )),
  );

  void _settings(BuildContext context) => showDialog<void>(context: context,
    builder: (context) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: const Text('Configurações'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(title: const Text('Modo simulado'),
            subtitle: const Text('Movimentos artificiais, sem rastreamento real'),
            value: settings.simulated, onChanged: (v) => refresh(() => settings.simulated = v)),
          SwitchListTile(title: const Text('Câmera frontal'), value: settings.frontCamera,
            onChanged: (v) => refresh(() => settings.frontCamera = v)),
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

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.settings});
  final GameSettings settings;
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  late final PoseSource source;
  late final BalloonMatch match;
  late final BalloonGame game;
  final audio = AudioPlayer();
  StreamSubscription<PoseFrame>? subscription;
  PlayStage stage = PlayStage.preparation;
  String? error;
  bool starting = false;
  Timer? refreshTimer;
  static const methods = MethodChannel('mobile_games/camera');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    source = widget.settings.simulated ? SimulatedPoseSource() : NativePoseSource();
    match = BalloonMatch(difficulty: widget.settings.difficulty);
    game = BalloonGame(match);
    match.onPop = () {
      if (widget.settings.sound) audio.play(AssetSource('audio/pop.wav'));
    };
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
          'front': widget.settings.frontCamera, 'mirror': widget.settings.mirror,
        });
      }
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
    source.stop();
    source.dispose();
    match.removeListener(_refresh);
    match.dispose();
    audio.dispose();
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
      Positioned.fill(child: IgnorePointer(child: GameWidget(game: game,
          backgroundBuilder: (_) => const SizedBox.expand()))),
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(
          match, widget.settings.debug)))),
      Positioned(left: 14, top: 12, child: _score(1, p1, PlayerId.player1)),
      Positioned(right: 14, top: 12, child: _score(2, p2, PlayerId.player2)),
      Positioned(top: 12, left: 0, right: 0, child: Center(child: Chip(
          label: Text(stage == PlayStage.match ? '${match.remaining.ceil()} s' : 'Mobile Games')))),
      if (source.simulated) const Positioned(left: 12, bottom: 10,
          child: Chip(label: Text('MODO SIMULADO · sem câmera real'))),
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
              '${DateTime.now().millisecondsSinceEpoch - tracking.lastSeenMs} ms idade'),
        ]);

  String _stateLabel(PlayerTracking p) {
    if (p.state == PlayerState.outside) { return 'Fora da área · volte à sua metade'; }
    if (p.frame == null || !p.frame!.detected ||
        DateTime.now().millisecondsSinceEpoch - p.lastSeenMs > 300) { return 'Procurando'; }
    return p.state == PlayerState.ready ? 'Pronto' : 'Detectado';
  }

  Widget _stagePanel(PlayerTracking p1, PlayerTracking p2) {
    if (stage == PlayStage.preparation) { return _panel(
      'Fique em sua metade, com corpo e mãos visíveis.',
      'Uma pessoa em cada região. Mantenha distância da linha central.',
      'Calibrar', () => setState(() => stage = PlayStage.calibration)); }
    if (stage == PlayStage.calibration) { return _panel(
      'Calibração', 'Erga e mova as mãos para marcar o alcance de cada jogador.',
      'Começar partida', p1.state == PlayerState.ready && p2.state == PlayerState.ready
          ? () { match.begin(); setState(() => stage = PlayStage.match); } : null); }
    if (stage == PlayStage.result) { return _panel(match.winner,
      'Jogador 1: ${match.scores[PlayerId.player1]} · Jogador 2: ${match.scores[PlayerId.player2]}',
      'Jogar novamente', () => setState(() => stage = PlayStage.calibration)); }
    if (match.pausedForTracking) { return _panel('Partida pausada',
        'Reposicionem-se nas próprias regiões para continuar.', 'Aguardando jogadores', null); }
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
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height),
      Paint()..color = const Color(0xBBFFFFFF)..strokeWidth = 2);
    if (!debug) return;
    for (final id in PlayerId.values) {
      final tracking = match.players[id]!;
      for (final point in tracking.smoothed.values) {
        canvas.drawCircle(Offset((point.dx + id.index) * size.width / 2,
            point.dy * size.height), 5, Paint()..color = id.index == 0
                ? const Color(0xFF58D5FF) : const Color(0xFFFF73B8));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) => true;
}
