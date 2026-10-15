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
