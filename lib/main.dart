import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/debug/fps_overlay.dart';
import 'ui/hud/game_hud.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Вождению и стрельбе в открытом мире нужны обе ориентации — HUD
  // подстраивается под ориентацию, а не фиксируется на одной (см. GameHud).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CrimeOrenApp());
}

class CrimeOrenApp extends StatelessWidget {
  const CrimeOrenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crime Oren',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const GameRoot(),
    );
  }
}

final _debugOverlayController = DebugOverlayController();

class GameRoot extends StatelessWidget {
  const GameRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final content = GameHud(debugOverlay: _debugOverlayController);

    // !kReleaseMode, а не kDebugMode: производительность имеет смысл мерить
    // только в --profile (debug-числа ничего не значат — ассерты, нет AOT),
    // а в profile-сборке kDebugMode уже false — оверлей с FPS пропадал ровно
    // в том режиме, ради которого он нужен. Из релиза он всё так же исключён.
    if (!kReleaseMode) {
      return FpsOverlay(controller: _debugOverlayController, child: content);
    }
    return content;
  }
}
