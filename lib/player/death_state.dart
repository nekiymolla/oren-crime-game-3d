/// Момент последней смерти игрока — расшаренный стейт, как ArrestState
/// (см. police/arrest_state.dart): Game пишет [trigger], HUD показывает
/// баннер, пока [isRecent].
class DeathState {
  static const Duration bannerDuration = Duration(milliseconds: 3500);

  DateTime? _lastDeathAt;

  void trigger() => _lastDeathAt = DateTime.now();

  bool get isRecent {
    final last = _lastDeathAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < bannerDuration;
  }
}

final DeathState deathState = DeathState();
