import 'dart:math' as math;

import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'audio_mix.dart';

/// Звук игры (ТЗ, раздел 22): пространственный — громкость зависит от
/// расстояния до источника, уши на камере (движок без AudioListener
/// следует за основной камерой). Бэкенд — SoLoud
/// (`flutter_scene_soloud`), клипы — assets/sounds/*.wav, синтезированные
/// tools/audio/generate_sounds.py.
///
/// Если звук не поднялся (нет аудиоустройства, ошибка плагина), система
/// молча выключается: игра без звука лучше, чем игра, которая падает.
class AudioSystem {
  AudioSystem(this.scene);

  final Scene scene;
  final math.Random _random = math.Random();

  late final SoloudAudioEngine _engine;
  final Map<String, AudioClip> _clips = {};
  bool _ready = false;

  AudioBus? _sfx;
  AudioBus? _ambience;
  AudioBus? _ui;

  /// Петли, которые живут всю игру: двигатель и визг шин машины игрока
  /// (их узел ставится на машину каждый кадр), погода и город (без
  /// позиции — "вокруг").
  final Node _vehicleEmitter = Node();
  ClipAudioSource? _engineLoop;
  ClipAudioSource? _screechLoop;
  ClipAudioSource? _rainLoop;
  ClipAudioSource? _windLoop;
  ClipAudioSource? _cityLoop;

  /// Сирены патрульных машин: узел машины -> источник на ней.
  final Map<Node, ClipAudioSource> _sirens = {};

  final FootstepTimer _footsteps = FootstepTimer();
  late final ThunderScheduler _thunder = ThunderScheduler(_random);

  static const List<String> _clipNames = [
    'gunshot',
    'bullet_impact',
    'reload',
    'engine_loop',
    'tire_screech_loop',
    'crash',
    'siren_loop',
    'footstep',
    'rain_loop',
    'wind_loop',
    'thunder',
    'city_loop',
    'pickup',
    'purchase',
    'hurt',
    'wasted',
  ];

  /// Затухание выстрелов: слышно далеко (на 40 м — ~15% громкости).
  final AudioAttenuation _loud = AudioAttenuation(minDistance: 2.0, maxDistance: 150.0, rolloffFactor: 0.3);

  /// Обычные звуки мира: шаги, рикошеты.
  final AudioAttenuation _near = AudioAttenuation(minDistance: 1.0, maxDistance: 40.0, rolloffFactor: 1.0);

  /// Подключить движок к сцене и загрузить клипы. Не бросает исключений.
  Future<void> load() async {
    try {
      _engine = SoloudAudioEngine(maxActiveVoices: 32);
      scene.root.addComponent(_engine);
      for (final name in _clipNames) {
        _clips[name] = await _engine.loadClip('assets/sounds/$name.wav');
      }
      _sfx = _engine.createBus('sfx');
      _ambience = _engine.createBus('ambience');
      _ui = _engine.createBus('ui');
      _ready = true;
    } on Object catch (error) {
      // ignore: avoid_print
      print('Звук не поднялся, играем без него: $error');
      return;
    }

    _engineLoop = _loop('engine_loop', bus: _sfx, positional: true, attenuation: _near);
    _screechLoop = _loop('tire_screech_loop', bus: _sfx, positional: true, attenuation: _near);
    _vehicleEmitter
      ..addComponent(_engineLoop!)
      ..addComponent(_screechLoop!);
    scene.add(_vehicleEmitter);

    final ambienceNode = Node();
    _rainLoop = _loop('rain_loop', bus: _ambience);
    _windLoop = _loop('wind_loop', bus: _ambience);
    _cityLoop = _loop('city_loop', bus: _ambience);
    ambienceNode
      ..addComponent(_rainLoop!)
      ..addComponent(_windLoop!)
      ..addComponent(_cityLoop!);
    scene.add(ambienceNode);
    for (final loop in [_rainLoop!, _windLoop!, _cityLoop!]) {
      loop.play();
    }
  }

  ClipAudioSource _loop(String name, {AudioBus? bus, bool positional = false, AudioAttenuation? attenuation}) =>
      ClipAudioSource(
        clip: _clips[name],
        looping: true,
        volume: 0.0,
        positional: positional,
        attenuation: attenuation,
        bus: bus,
      );

  /// Вкл/выкл весь звук (debug-панель).
  bool get muted => _ready && _engine.masterVolume == 0.0;
  set muted(bool value) {
    if (_ready) _engine.masterVolume = value ? 0.0 : 1.0;
  }

  void _oneShot(
    String name, {
    vm.Vector3? at,
    double volume = 1.0,
    double pitch = 1.0,
    AudioBus? bus,
    AudioAttenuation? attenuation,
  }) {
    if (!_ready) return;
    final clip = _clips[name];
    if (clip == null) return;
    _engine.playOneShot(
      clip,
      position: at,
      volume: volume,
      pitch: pitch,
      bus: bus ?? _sfx,
      attenuation: attenuation ?? _near,
    );
  }

  /// Небольшой разброс высоты — одинаковые звуки подряд не звучат
  /// как пулемёт одного сэмпла.
  double _vary(double spread) => 1.0 + (_random.nextDouble() * 2 - 1) * spread;

  // --- События ------------------------------------------------------------

  void gunshot(vm.Vector3 at, {bool police = false}) =>
      _oneShot('gunshot', at: at, pitch: (police ? 0.9 : 1.0) * _vary(0.05), attenuation: _loud);

  void bulletImpact(vm.Vector3 at) => _oneShot('bullet_impact', at: at, volume: 0.7, pitch: _vary(0.15));

  void reload(vm.Vector3 at) => _oneShot('reload', at: at, volume: 0.8);

  void crash(vm.Vector3 at, double impactSpeed) =>
      _oneShot('crash', at: at, volume: (impactSpeed / 15.0).clamp(0.3, 1.0), pitch: _vary(0.08), attenuation: _loud);

  void pickup() => _oneShot('pickup', bus: _ui, volume: 0.7);

  void purchase() => _oneShot('purchase', bus: _ui, volume: 0.8);

  void saved() => _oneShot('pickup', bus: _ui, volume: 0.6, pitch: 0.75);

  void hurt() => _oneShot('hurt', bus: _ui, volume: 0.8, pitch: _vary(0.1));

  void wasted() => _oneShot('wasted', bus: _ui, volume: 0.9);

  void busted() => _oneShot('wasted', bus: _ui, volume: 0.8, pitch: 1.3);

  // --- Покадровое ---------------------------------------------------------

  /// Петли и шаги. [vehicle] — машина игрока, если он за рулём.
  void update(
    double dt, {
    required vm.Vector3 playerFeet,
    required double playerSpeed,
    required bool playerGrounded,
    ({vm.Vector3 position, double speed, double maxSpeed, double driftFactor})? vehicle,
    required double rain,
    required double snow,
    required double wind,
    required double nightFactor,
    required double lightningFlash,
    required Iterable<Node> policeCars,
  }) {
    if (!_ready) return;

    // Шаги — только пешком.
    if (vehicle == null && _footsteps.update(dt, speed: playerSpeed, grounded: playerGrounded)) {
      _oneShot('footstep', at: playerFeet, volume: 0.45, pitch: _vary(0.12));
    }

    // Двигатель и шины машины игрока.
    final engine = _engineLoop!;
    final screech = _screechLoop!;
    if (vehicle != null) {
      _vehicleEmitter.position = vehicle.position + vm.Vector3(0, 0.6, 0);
      if (!engine.isPlaying) engine.play();
      if (!screech.isPlaying) screech.play();
      engine
        ..pitch = enginePitch(vehicle.speed, vehicle.maxSpeed)
        ..volume = engineVolume(vehicle.speed, vehicle.maxSpeed);
      screech.volume = screechVolume(driftFactor: vehicle.driftFactor, speed: vehicle.speed);
    } else {
      if (engine.isPlaying) engine.stop();
      if (screech.isPlaying) screech.stop();
    }

    // Погода и город.
    final mix = ambienceMix(rain: rain, snow: snow, wind: wind, nightFactor: nightFactor, inVehicle: vehicle != null);
    _rainLoop!.volume = mix.rain;
    _windLoop!.volume = mix.wind;
    _cityLoop!.volume = mix.city;
    for (var i = _thunder.update(dt, lightningFlash); i > 0; i--) {
      _oneShot('thunder', bus: _ambience, volume: 0.9, pitch: _vary(0.1));
    }

    _syncSirens(policeCars);
  }

  /// Сирена на каждой патрульной машине: источник — дочерний узел машины,
  /// так что едет вместе с ней (с доплером) и замолкает, когда машину
  /// убирают со сцены.
  void _syncSirens(Iterable<Node> policeCars) {
    final current = policeCars.toSet();
    _sirens.removeWhere((car, _) => !current.contains(car));
    for (final car in current) {
      if (_sirens.containsKey(car)) continue;
      final siren = ClipAudioSource(
        clip: _clips['siren_loop'],
        looping: true,
        volume: 0.55,
        pitch: _vary(0.04),
        bus: _sfx,
        attenuation: AudioAttenuation(minDistance: 6.0, maxDistance: 250.0, rolloffFactor: 0.5),
      );
      car.add(Node()
        ..position = vm.Vector3(0, 1.6, 0)
        ..addComponent(siren));
      siren.play();
      _sirens[car] = siren;
    }
  }
}
