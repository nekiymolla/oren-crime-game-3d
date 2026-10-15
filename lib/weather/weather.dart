import 'dart:math' as math;

/// Состояния погоды (ТЗ, разделы 15-16). Каждое — набор чисел
/// [WeatherParams]; между состояниями погода переходит плавно.
enum WeatherKind {
  clear('ясно'),
  partlyCloudy('малооблачно'),
  cloudy('облачно'),
  overcast('пасмурно'),
  fog('туман'),
  // Осадки — лестницей по силе: туман растёт вместе с ней, слабый дождь
  // и слабый снег — совсем без тумана (раньше дождь был один и сразу
  // затягивал всё серой пеленой).
  drizzle('слабый дождь'),
  rain('дождь'),
  heavyRain('ливень'),
  storm('гроза'),
  lightSnow('слабый снег'),
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
    this.wetness = 0.0,
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

  /// Насколько мокрый асфальт (0..1): копится в дождь и сохнет после
  /// своим темпом (WeatherSystem). В пресетах не задаётся — считается из
  /// силы дождя ([wetnessForRain]).
  final double wetness;

  /// К какой мокроте стремится асфальт при такой силе дождя: слабый
  /// дождь мочит не до конца, обычный и сильнее — полностью.
  static double wetnessForRain(double rain) => rain > 0.05 ? math.min(1.0, rain / 0.5) : 0.0;

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
      wetness: mix(a.wetness, b.wetness),
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
  // Слабые осадки — тумана меньше даже фоновой дымки ясной погоды: под
  // серым небом та читалась как пелена.
  WeatherKind.drizzle: WeatherParams(
    cloudCover: 0.65,
    fogDensity: 0.0007,
    rain: 0.3,
    wind: 0.2,
    sunRays: 0.2,
    saturation: -0.08,
    temperature: -0.03,
  ),
  WeatherKind.rain: WeatherParams(
    cloudCover: 0.85,
    fogDensity: 0.0028,
    rain: 0.6,
    wind: 0.35,
    sunRays: 0.0,
    saturation: -0.14,
    temperature: -0.06,
  ),
  WeatherKind.heavyRain: WeatherParams(
    cloudCover: 0.95,
    fogDensity: 0.0055,
    rain: 0.9,
    wind: 0.55,
    sunRays: 0.0,
    saturation: -0.2,
    temperature: -0.08,
  ),
  WeatherKind.storm: WeatherParams(
    cloudCover: 1.0,
    fogDensity: 0.0075,
    rain: 1.0,
    wind: 0.9,
    lightning: 1.0,
    sunRays: 0.0,
    saturation: -0.22,
    contrast: 0.1,
    temperature: -0.12,
  ),
  WeatherKind.lightSnow: WeatherParams(
    cloudCover: 0.7,
    fogDensity: 0.0007,
    snow: 0.3,
    wind: 0.1,
    sunRays: 0.15,
    saturation: -0.1,
    temperature: -0.1,
    snowCover: 0.45,
  ),
  WeatherKind.snow: WeatherParams(
    cloudCover: 0.9,
    fogDensity: 0.004,
    snow: 0.6,
    wind: 0.2,
    sunRays: 0.0,
    saturation: -0.18,
    temperature: -0.15,
    snowCover: 0.85,
  ),
  WeatherKind.blizzard: WeatherParams(
    cloudCover: 1.0,
    fogDensity: 0.03,
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
    : _fromParams = weatherPresets[initial]!,
      _to = initial,
      _random = random ?? math.Random();

  /// Сколько реальных секунд длится переход между состояниями.
  static const double transitionSeconds = 25.0;

  final math.Random _random;
  /// Откуда идёт переход — снимок того, что было видно в момент смены, а
  /// не пресет: иначе смена посреди перехода давала скачок, а частые смены
  /// (кнопка в debug-панели) каждый раз начинали со старой погоды, и
  /// картинка почти не менялась.
  WeatherParams _fromParams;
  WeatherKind _to;
  double _progress = 1.0;
  double _hoursUntilChange = 3.0;
  double _snowCover = 0.0;
  double _wetness = 0.0;

  /// Куда идёт погода (после перехода — текущая).
  WeatherKind get kind => _to;

  /// Смешанные параметры прямо сейчас.
  WeatherParams get params {
    final t = _progress * _progress * (3 - 2 * _progress); // smoothstep
    final blended = WeatherParams.lerp(_fromParams, weatherPresets[_to]!, t);
    // Снег и мокрый асфальт копятся и сходят своим темпом, а не вместе с
    // переходом.
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
      wetness: _wetness,
    );
  }

  /// Сменить погоду: плавно (от того, что видно сейчас) или [immediately]
  /// — сразу, для debug-панели.
  void setWeather(WeatherKind kind, {bool immediately = false}) {
    if (kind == _to && !immediately) return;
    _fromParams = params;
    _to = kind;
    _progress = immediately ? 1.0 : 0.0;
  }

  /// Следующее состояние по кругу — для кнопки в debug-панели, сразу.
  void cycle() => setWeather(WeatherKind.values[(_to.index + 1) % WeatherKind.values.length], immediately: true);

  void update(double realSeconds, {required double gameHoursPassed, required int dayOfYear}) {
    if (_progress < 1.0) {
      _progress = math.min(1.0, _progress + realSeconds / transitionSeconds);
    }

    // Снежный покров: копится ~1.5 минуты снегопада, тает ~4 минуты.
    final target = params.snow > 0.05 ? weatherPresets[_to]!.snowCover : 0.0;
    final rate = target > _snowCover ? realSeconds / 90.0 : realSeconds / 240.0;
    _snowCover += (target - _snowCover).clamp(-rate, rate);

    // Мокрый асфальт: намокает за ~40 секунд дождя, сохнет ~4 минуты —
    // после дождя улицы ещё долго блестят.
    final wetTarget = WeatherParams.wetnessForRain(params.rain);
    final wetRate = wetTarget > _wetness ? realSeconds / 40.0 : realSeconds / 240.0;
    _wetness += (wetTarget - _wetness).clamp(-wetRate, wetRate);

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
      add(WeatherKind.drizzle, season == Season.winter ? 0 : 1);
      add(WeatherKind.lightSnow, season == Season.winter ? 2 : 0);
    case WeatherKind.overcast:
      add(WeatherKind.cloudy, 2);
      add(WeatherKind.drizzle, season == Season.winter ? 0 : 2);
      add(WeatherKind.rain, season == Season.winter ? 0 : 1);
      add(WeatherKind.lightSnow, season == Season.winter ? 3 : (season == Season.autumn ? 0.3 : 0));
      add(WeatherKind.fog, season == Season.summer ? 0.3 : 1);
    case WeatherKind.fog:
      add(WeatherKind.overcast, 2);
      add(WeatherKind.cloudy, 2);
    // Дождь — вверх и вниз по лестнице на одну ступень, без прыжков.
    case WeatherKind.drizzle:
      add(WeatherKind.overcast, 2);
      add(WeatherKind.cloudy, 1);
      add(WeatherKind.rain, 2);
      add(WeatherKind.drizzle, 1);
    case WeatherKind.rain:
      add(WeatherKind.drizzle, 2);
      add(WeatherKind.heavyRain, season == Season.summer ? 2 : 1);
      add(WeatherKind.rain, 1);
    case WeatherKind.heavyRain:
      add(WeatherKind.rain, 3);
      add(WeatherKind.storm, season == Season.summer ? 2 : 0.4);
    case WeatherKind.storm:
      add(WeatherKind.heavyRain, 3);
      add(WeatherKind.rain, 1);
    case WeatherKind.lightSnow:
      add(WeatherKind.overcast, 2);
      add(WeatherKind.snow, season == Season.winter ? 2 : 0.3);
      add(WeatherKind.lightSnow, 1);
    case WeatherKind.snow:
      add(WeatherKind.lightSnow, 2);
      add(WeatherKind.blizzard, season == Season.winter ? 1 : 0.2);
      add(WeatherKind.snow, 1);
    case WeatherKind.blizzard:
      add(WeatherKind.snow, 3);
      add(WeatherKind.lightSnow, 1);
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
