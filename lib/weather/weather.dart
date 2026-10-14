import 'dart:math' as math;

/// Состояния погоды (ТЗ, разделы 15-16). Каждое — набор чисел
/// [WeatherParams]; между состояниями погода переходит плавно.
enum WeatherKind {
  clear('ясно'),
  partlyCloudy('малооблачно'),
  cloudy('облачно'),
  overcast('пасмурно'),
  fog('туман'),
  rain('дождь'),
  storm('гроза'),
  snow('снег'),
  blizzard('метель'),
  heat('жара');

  const WeatherKind(this.label);

  /// Подпись для HUD/debug-панели.
  final String label;
}

/// Всё, чем погода влияет на картинку, — числами, которые можно плавно
/// смешивать ([lerp]). Сами эффекты (туман, лучи, капли) применяет
/// WeatherView; здесь только данные.
class WeatherParams {
  const WeatherParams({
    this.cloudCover = 0.0,
    this.fogDensity = 0.0015,
    this.fogWarmth = 0.0,
    this.rain = 0.0,
    this.snow = 0.0,
    this.wind = 0.1,
    this.lightning = 0.0,
    this.sunRays = 1.0,
    this.saturation = 0.0,
    this.contrast = 0.0,
    this.temperature = 0.0,
    this.snowCover = 0.0,
  });

  /// 0 — чистое небо, 1 — сплошная облачность: гасит солнце, тени и лучи,
  /// обесцвечивает небо в серое.
  final double cloudCover;

  /// Плотность экспоненциального тумана. Даже в ясную погоду не ноль —
  /// лёгкая воздушная перспектива делает дальние дома голубее.
  final double fogDensity;

  /// 0 — туман цвета горизонта, 1 — тёплое марево (жара).
  final double fogWarmth;

  /// Интенсивность осадков 0..1.
  final double rain;
  final double snow;

  /// Ветер 0..1 — наклон дождя, снос снега.
  final double wind;

  /// Частота молний 0..1 (гроза — 1).
  final double lightning;

  /// Сила лучей солнца (god rays) и бликов: в ясную — полная, в жару —
  /// больше полной, при сплошной облачности — ноль.
  final double sunRays;

  /// Поправки цветокоррекции к базовой (Game._applyEnvironmentSettings).
  final double saturation;
  final double contrast;
  final double temperature;

  /// К чему стремится снежный покров на земле и кронах (0..1).
  final double snowCover;

  static WeatherParams lerp(WeatherParams a, WeatherParams b, double t) {
    double mix(double x, double y) => x + (y - x) * t;
    return WeatherParams(
      cloudCover: mix(a.cloudCover, b.cloudCover),
      fogDensity: mix(a.fogDensity, b.fogDensity),
      fogWarmth: mix(a.fogWarmth, b.fogWarmth),
      rain: mix(a.rain, b.rain),
      snow: mix(a.snow, b.snow),
      wind: mix(a.wind, b.wind),
      lightning: mix(a.lightning, b.lightning),
      sunRays: mix(a.sunRays, b.sunRays),
      saturation: mix(a.saturation, b.saturation),
      contrast: mix(a.contrast, b.contrast),
      temperature: mix(a.temperature, b.temperature),
      snowCover: mix(a.snowCover, b.snowCover),
    );
  }
}

/// Числа каждого состояния. Подобраны на глаз под картинку, а не под
/// метеорологию.
const Map<WeatherKind, WeatherParams> weatherPresets = {
  WeatherKind.clear: WeatherParams(sunRays: 1.0, saturation: 0.05),
  WeatherKind.partlyCloudy: WeatherParams(cloudCover: 0.3, sunRays: 0.85, wind: 0.2),
  WeatherKind.cloudy: WeatherParams(cloudCover: 0.6, fogDensity: 0.003, sunRays: 0.45, wind: 0.3, saturation: -0.05),
  WeatherKind.overcast: WeatherParams(
    cloudCover: 0.92,
    fogDensity: 0.005,
    sunRays: 0.0,
    wind: 0.3,
    saturation: -0.2,
    contrast: -0.05,
    temperature: -0.05,
  ),
  WeatherKind.fog: WeatherParams(
    cloudCover: 0.8,
    fogDensity: 0.035,
    sunRays: 0.2,
    wind: 0.05,
    saturation: -0.25,
    contrast: -0.1,
  ),
  WeatherKind.rain: WeatherParams(
    cloudCover: 0.95,
    fogDensity: 0.008,
    rain: 0.7,
    wind: 0.4,
    sunRays: 0.0,
    saturation: -0.2,
    temperature: -0.08,
  ),
  WeatherKind.storm: WeatherParams(
    cloudCover: 1.0,
    fogDensity: 0.018,
    rain: 1.0,
    wind: 0.9,
    lightning: 1.0,
    sunRays: 0.0,
    saturation: -0.25,
    contrast: 0.1,
    temperature: -0.12,
  ),
  WeatherKind.snow: WeatherParams(
    cloudCover: 0.9,
    fogDensity: 0.009,
    snow: 0.6,
    wind: 0.2,
    sunRays: 0.0,
    saturation: -0.2,
    temperature: -0.15,
    snowCover: 0.85,
  ),
  WeatherKind.blizzard: WeatherParams(
    cloudCover: 1.0,
    fogDensity: 0.045,
    snow: 1.0,
    wind: 1.0,
    sunRays: 0.0,
    saturation: -0.35,
    temperature: -0.2,
    snowCover: 1.0,
  ),
  WeatherKind.heat: WeatherParams(
    fogDensity: 0.005,
    fogWarmth: 1.0,
    sunRays: 1.3,
    wind: 0.05,
    saturation: 0.15,
    contrast: 0.05,
    temperature: 0.18,
  ),
};

/// Текущая погода: состояние, плавный переход к следующему и смена сама
/// собой раз в несколько игровых часов — с учётом сезона (в октябре
/// Оренбурга дожди и пасмурно часто, снег — редкость, жары не бывает).
class WeatherSystem {
  WeatherSystem({WeatherKind initial = WeatherKind.clear, math.Random? random})
    : _from = initial,
      _to = initial,
      _random = random ?? math.Random();

  /// Сколько реальных секунд длится переход между состояниями.
  static const double transitionSeconds = 25.0;

  final math.Random _random;
  WeatherKind _from;
  WeatherKind _to;
  double _progress = 1.0;
  double _hoursUntilChange = 3.0;
  double _snowCover = 0.0;

  /// Куда идёт погода (после перехода — текущая).
  WeatherKind get kind => _to;

  /// Смешанные параметры прямо сейчас.
  WeatherParams get params {
    final t = _progress * _progress * (3 - 2 * _progress); // smoothstep
    final blended = WeatherParams.lerp(weatherPresets[_from]!, weatherPresets[_to]!, t);
    // Снег на земле копится и тает своим темпом, а не вместе с переходом.
    return WeatherParams(
      cloudCover: blended.cloudCover,
      fogDensity: blended.fogDensity,
      fogWarmth: blended.fogWarmth,
      rain: blended.rain,
      snow: blended.snow,
      wind: blended.wind,
      lightning: blended.lightning,
      sunRays: blended.sunRays,
      saturation: blended.saturation,
      contrast: blended.contrast,
      temperature: blended.temperature,
      snowCover: _snowCover,
    );
  }

  /// Сменить погоду (debug-панель, будущие миссии).
  void setWeather(WeatherKind kind) {
    if (kind == _to) return;
    // Новый переход начинается с того, что видно сейчас: подменяем "откуда"
    // на ближайшее из двух, чтобы не было скачка.
    _from = _progress < 0.5 ? _from : _to;
    _to = kind;
    _progress = 0.0;
  }

  /// Следующее состояние по кругу — для кнопки в debug-панели.
  void cycle() => setWeather(WeatherKind.values[(_to.index + 1) % WeatherKind.values.length]);

  void update(double realSeconds, {required double gameHoursPassed, required int dayOfYear}) {
    if (_progress < 1.0) {
      _progress = math.min(1.0, _progress + realSeconds / transitionSeconds);
    }

    // Снежный покров: копится ~1.5 минуты снегопада, тает ~4 минуты.
    final target = params.snow > 0.05 ? weatherPresets[_to]!.snowCover : 0.0;
    final rate = target > _snowCover ? realSeconds / 90.0 : realSeconds / 240.0;
    _snowCover += (target - _snowCover).clamp(-rate, rate);

    _hoursUntilChange -= gameHoursPassed;
    if (_hoursUntilChange <= 0) {
      _hoursUntilChange = 2.0 + _random.nextDouble() * 4.0;
      setWeather(nextWeather(_to, dayOfYear, _random));
    }
  }
}

/// Следующая погода — случайно, но правдоподобно: из ясной сразу в метель
/// не бывает, а снег и жара зависят от сезона.
WeatherKind nextWeather(WeatherKind current, int dayOfYear, math.Random random) {
  final season = seasonOf(dayOfYear);
  // Соседи по "шкале облачности" и осадки по сезону.
  final weights = <WeatherKind, double>{
    for (final kind in WeatherKind.values) kind: 0.0,
  };
  void add(WeatherKind kind, double weight) => weights[kind] = weights[kind]! + weight;

  switch (current) {
    case WeatherKind.clear || WeatherKind.heat:
      add(WeatherKind.clear, 2);
      add(WeatherKind.partlyCloudy, 3);
      add(WeatherKind.heat, season == Season.summer ? 2 : 0);
    case WeatherKind.partlyCloudy:
      add(WeatherKind.clear, 2);
      add(WeatherKind.cloudy, 3);
      add(WeatherKind.partlyCloudy, 1);
    case WeatherKind.cloudy:
      add(WeatherKind.partlyCloudy, 2);
      add(WeatherKind.overcast, 2);
      add(WeatherKind.rain, season == Season.winter ? 0 : 1);
      add(WeatherKind.snow, season == Season.winter ? 2 : 0);
    case WeatherKind.overcast:
      add(WeatherKind.cloudy, 2);
      add(WeatherKind.rain, season == Season.winter ? 0 : 3);
      add(WeatherKind.snow, season == Season.winter ? 3 : (season == Season.autumn ? 0.3 : 0));
      add(WeatherKind.fog, season == Season.summer ? 0.3 : 1);
    case WeatherKind.fog:
      add(WeatherKind.overcast, 2);
      add(WeatherKind.cloudy, 2);
    case WeatherKind.rain:
      add(WeatherKind.overcast, 3);
      add(WeatherKind.storm, season == Season.summer ? 2 : 0.5);
      add(WeatherKind.rain, 1);
    case WeatherKind.storm:
      add(WeatherKind.rain, 3);
      add(WeatherKind.overcast, 1);
    case WeatherKind.snow:
      add(WeatherKind.overcast, 2);
      add(WeatherKind.blizzard, season == Season.winter ? 1 : 0.2);
      add(WeatherKind.snow, 1);
    case WeatherKind.blizzard:
      add(WeatherKind.snow, 3);
      add(WeatherKind.overcast, 1);
  }

  final total = weights.values.fold(0.0, (a, b) => a + b);
  var pick = random.nextDouble() * total;
  for (final entry in weights.entries) {
    pick -= entry.value;
    if (pick <= 0 && entry.value > 0) return entry.key;
  }
  return WeatherKind.overcast;
}

enum Season { winter, spring, summer, autumn }

Season seasonOf(int dayOfYear) {
  if (dayOfYear < 60 || dayOfYear >= 335) return Season.winter;
  if (dayOfYear < 152) return Season.spring;
  if (dayOfYear < 244) return Season.summer;
  return Season.autumn;
}
