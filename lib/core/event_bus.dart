import 'dart:async';

/// Базовый тип для всех игровых событий между системами (например,
/// VehicleEnteredEvent, WantedLevelChangedEvent). Системы общаются через
/// [EventBus], а не держат прямые ссылки друг на друга.
abstract class GameEvent {
  const GameEvent();
}

/// Единая на весь процесс типизированная шина событий для развязки систем.
///
/// Пример:
/// ```dart
/// final sub = eventBus.on<WantedLevelChangedEvent>().listen((e) => ...);
/// eventBus.fire(WantedLevelChangedEvent(level: 2));
/// sub.cancel();
/// ```
class EventBus {
  final StreamController<GameEvent> _controller =
      StreamController<GameEvent>.broadcast();

  Stream<T> on<T extends GameEvent>() =>
      _controller.stream.where((event) => event is T).cast<T>();

  void fire(GameEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}

/// Общий экземпляр на игровую сессию. Системы получают его через
/// конструктор; глобальная переменная нужна только как точка доступа
/// для composition root при старте приложения.
final EventBus eventBus = EventBus();
