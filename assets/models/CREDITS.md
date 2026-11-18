# Сторонние модели

Все модели — из бесплатных паков с лицензией, разрешающей коммерческое
использование (ТЗ, раздел 31). В репозитории лежат уже переработанные
версии (см. скрипты в tools/assets/), исходные архивы — нет.

## Персонажи — assets/models/characters/

Quaternius — Ultimate Modular Men Pack и Ultimate Modular Women Pack
(https://quaternius.com, скачаны с https://poly.pizza/u/Quaternius).
Лицензия: CC0 1.0. Пять моделей женского пака (Suit, Worker, Soldier, Sci-Fi,
Witch) poly.pizza помечает как CC-BY 3.0, поэтому указываем автора:
**модели персонажей — Quaternius**.

Подготовка: `tools/assets/fetch_polypizza.py` (скачать бандл) ->
`tools/assets/prepare_characters.mjs` (материалы в цвета вершин, один
draw call, отбор анимаций).

## Главный герой — assets/models/characters/male_camper.glb

VibeAssets, текстурированный мужчина в клетчатой рубашке, CC0 1.0:
https://vibeassets.io/a/zpepqtthci
Исходник с родными Walk/Run:
https://vibeassets.io/download/zpepqtthci?combined=1
SHA-256: `940444190abb1f3731675678277e9c3f27be1783966987f0a02ccd9fd1405193`.

Подготовка: `tools/assets/prepare_player.mjs`. Сохранены родные ходьба и
бег; остальные игровые позы построены скриптом под его собственный
24-костный скелет. Исправлены единицы скелета и inverse bind matrices,
стопы поставлены на землю по деформированной геометрии. Одна текстура,
31 122 треугольника, итоговый GLB около 2.4 МБ. Метаданные и контрольные
границы поз — в male_camper.json. Используется только для игрока;
NPC пока используют Quaternius. Боевые позы и падение — прототипные,
физического ragdoll нет.

## Остальные машины — assets/models/vehicles/

Quaternius — Cars Bundle (https://poly.pizza/bundle/Cars-Bundle-FE5IWe6OMk).
Лицензия: CC0 1.0.

Подготовка: `tools/assets/prepare_vehicles.mjs` (колёса с опорой в центре,
роли материалов Paint/Glass/Headlights/TailLights/Siren_*, перед на +Z игры).

## Текстуры земли — assets/models/ground/

ambientCG — Grass004 и Ground037 (https://ambientcg.com). Лицензия: CC0 1.0.
Уменьшены до 512 px и упакованы в glb `tools/assets/prepare_ground.mjs`.

## Стартовый седан 80-х — assets/models/vehicles/sedan_80.glb

Grab3D — **1980s Sedan**, лицензия CC0 1.0.
Источник и сведения о лицензии:
https://grab3d.com/models/vehicles/1980s-sedan/
Прямой исходный файл:
https://grab3d.com/dl/1980s-sedan/1980s-sedan.glb

SHA-256 исходника:
`3c68f031d3d6833aa8c8b6bcceb636b4d7f18842815c2043a2bc1f44d7753a44`.

Подготовка: `tools/assets/prepare_classic_sedan.mjs` (Node-зависимости из
этой папки + Python/Pillow). Геометрия приведена к координатам игры,
колёса перецентрированы, фары и задние фонари выделены из атласа в роли
материалов. Исходные PBR-карты сохранены, большие уменьшены до 1024 px.
Размеры и центры колёс записаны рядом в `sedan_80.json`.

Это безымянная модель седана, не точная модель «Волги» или другого
реального автомобиля. Используется у стартовой машины; остальные
архетипы транспорта пока из паков Quaternius, указанных выше.

## Уличное благоустройство — assets/models/world/streets/

Процедурная геометрия проекта: дорожные панели, бордюры, фонари, лавочки,
турник и бетонный ограничитель. Генератор tools/assets/prepare_city_streets.mjs.
Маршруты и контуры площадок: © OpenStreetMap contributors, ODbL 1.0,
https://www.openstreetmap.org/copyright . Снимок 18.11.2026.
Положения отдельных фонарей, лавочек и посадок деревьев приблизительные,
это отмечено в assets/data/city_map.json. Подробности: docs/CITY.md.

Второй слой: ограды, урны, качели, горка, брусья, скейт-заезды и щиты —
процедурные модели проекта. Компоновка приблизительная, сохраняет
контуры площадок OSM. Генераторы: city_area_layout.mjs,
city_area_geometry.mjs; минеральное зерно покрытия — собственная
процедурная текстура prepare_urban_grain.py, без сторонних изображений.

## Интеграция теней газона

Функция CatcherSpotShadowVisibility в assets/shaders/ground.fmat основана
на flutter_scene 0.23.0 assets/materials/shadow_catcher.fmat.
Copyright (c) 2023 Brandon DeRosier, MIT. Полное уведомление:
docs/licenses/flutter_scene-MIT.txt.
