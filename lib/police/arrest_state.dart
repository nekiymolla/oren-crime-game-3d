/// Момент последнего ареста — расшаренный стейт того же вида, что и
/// WantedState (см. wanted_state.dart): Game пишет [trigger] в момент
/// поимки, HUD читает [isRecent] через свой Ticker, чтобы на пару секунд
/// показать баннер "ЗАДЕРЖАН", напрямую друг о друге не зная.
class ArrestState {
  static const Duration bannerDuration = Duration(seconds: 3);

  DateTime? _lastArrestAt;

  void trigger() => _lastArrestAt = DateTime.now();

  bool get isRecent {
    final last = _lastArrestAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < bannerDuration;
  }
}

final ArrestState arrestState = ArrestState();
