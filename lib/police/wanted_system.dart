import 'wanted_state.dart';

/// Правила уровня розыска — чистая (без Flutter) логика, читает/пишет
/// [WantedState]. Наезд на пешехода (см. PedestrianSystem.update,
/// возвращает число сбитых за кадр) сразу поднимает звёзды на это число;
/// превышение скорости — "лёгкое" нарушение, поднимает только до 1 звезды
/// само по себе, не эскалирует дальше. Без новых нарушений
/// [decayIntervalSeconds] звёзды снимаются по одной.
///
/// Пока нет полицейских NPC/погони — это следующая отдельная задача (см.
/// PROGRESS.md), здесь только сам счётчик и его затухание.
class WantedSystem {
  WantedSystem({this.speedThreshold = 22.0, this.decayIntervalSeconds = 10.0});

  /// м/с, выше которого вождение считается "опасным" (~80 км/ч).
  final double speedThreshold;
  final double decayIntervalSeconds;

  double _secondsSinceOffense = 0.0;

  void update(double dt, {int pedestrianHits = 0, bool isSpeeding = false}) {
    var offended = false;

    if (pedestrianHits > 0) {
      wantedState.stars += pedestrianHits;
      offended = true;
    }
    if (isSpeeding && wantedState.stars == 0) {
      wantedState.stars = 1;
      offended = true;
    }

    if (offended) {
      _secondsSinceOffense = 0.0;
      return;
    }

    if (wantedState.stars == 0) return;
    _secondsSinceOffense += dt;
    if (_secondsSinceOffense >= decayIntervalSeconds) {
      _secondsSinceOffense = 0.0;
      wantedState.stars -= 1;
    }
  }
}
