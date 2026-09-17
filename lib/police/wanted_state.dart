/// Уровень розыска игрока (0-5 звёзд, как в GTA) — расшаренный стейт,
/// как GameModeState (см. core/game_mode.dart): WantedSystem его пишет,
/// HUD его читает через свой Ticker (см. ui/hud/wanted_stars.dart),
/// напрямую друг о друге не зная. Пока без полицейских NPC/погони — это
/// отдельная следующая задача (см. PROGRESS.md), тут только сам счётчик.
class WantedState {
  static const int maxStars = 5;

  int _stars = 0;
  int get stars => _stars;
  set stars(int value) => _stars = value.clamp(0, maxStars);
}

final WantedState wantedState = WantedState();
