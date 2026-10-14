import 'package:vector_math/vector_math.dart' as vm;

import '../time/day_night.dart';
import 'weather.dart';

/// Как погода меняет свет и небо суточного цикла: облака гасят солнце и
/// тени и обесцвечивают небо в серое, вспышка молнии на миг освещает всё.
/// Чистая функция — проверяется тестами без движка.
SkyLighting applyWeather(SkyLighting sky, WeatherParams weather, {double lightningFlash = 0.0}) {
  final cloud = weather.cloudCover.clamp(0.0, 1.0);

  // Небо уходит в серое той же яркости, что было (днём светло-серое,
  // ночью тёмное) — иначе пасмурная ночь светилась бы.
  vm.Vector3 grayOf(vm.Vector3 color, double scale) {
    final luminance = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z;
    return vm.Vector3(0.95, 0.97, 1.0) * (luminance * scale);
  }

  final zenith = _mix(sky.zenithColor, grayOf(sky.horizonColor, 0.8), cloud * 0.9);
  final horizon = _mix(sky.horizonColor, grayOf(sky.horizonColor, 1.0), cloud * 0.9);

  // Прямой свет сквозь облака — не до нуля: сплошная облачность всё равно
  // пропускает рассеянный свет, а его часть берёт на себя небо.
  final direct = 1.0 - 0.85 * cloud;
  final sunDisk = sky.sunDiskColor * ((1 - cloud) * (1 - cloud) * (1 - cloud));
  final environment = sky.environmentIntensity * (1.0 - 0.2 * cloud);
  final unlit = sky.unlitTint * (0.65 + 0.35 * direct);

  final flash = lightningFlash.clamp(0.0, 1.0);
  final flashColor = vm.Vector3(0.75, 0.78, 0.95) * flash;

  return sky.copyWith(
    lightIntensity: sky.lightIntensity * direct,
    castsShadow: sky.castsShadow && cloud < 0.75,
    environmentIntensity: environment + 2.5 * flash,
    zenithColor: zenith + flashColor * 0.6,
    horizonColor: horizon + flashColor,
    sunDiskColor: sunDisk,
    unlitTint: unlit + vm.Vector3.all(0.5 * flash),
  );
}

vm.Vector3 _mix(vm.Vector3 a, vm.Vector3 b, double t) => a + (b - a) * t;
