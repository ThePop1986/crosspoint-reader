# PiccoOS — License Audit (A-03)

**Дата:** 2026-11-12 · **Ревизия:** CrossPoint `3a5bfac`, SDK `6a208c0`, simulator `84c3421`
**Метод:** чтение `LICENSE`, `licenses/*` и заголовков в исходниках на указанных коммитах. Это инженерный аудит, не юридическое заключение.

**Что означает «Confirmed» в этом документе:** Claude прочитал указанный файл на закреплённом коммите. Это не независимое подтверждение. Для проверки — постоянные ссылки ниже (открываются без клонирования).

| Файл | Постоянная ссылка |
|---|---|
| CrossPoint `LICENSE` | https://github.com/crosspoint-reader/crosspoint-reader/blob/3a5bfac375c293cb38f7e6e28f7736e7d451ef57/LICENSE |
| Сводка лицензий прошивки | https://github.com/crosspoint-reader/crosspoint-reader/blob/3a5bfac375c293cb38f7e6e28f7736e7d451ef57/licenses/README.md |
| Шрифты | https://github.com/crosspoint-reader/crosspoint-reader/blob/3a5bfac375c293cb38f7e6e28f7736e7d451ef57/licenses/fonts.txt |
| Заимствованный код | https://github.com/crosspoint-reader/crosspoint-reader/blob/3a5bfac375c293cb38f7e6e28f7736e7d451ef57/licenses/borrowed-code.txt |
| Переносы | https://github.com/crosspoint-reader/crosspoint-reader/blob/3a5bfac375c293cb38f7e6e28f7736e7d451ef57/licenses/hyphenation.txt |
| FreeInk SDK `LICENSE` | https://github.com/Free-Ink/freeink-sdk/blob/6a208c0c46cce99bafa334bc4f171f5e558c5195/LICENSE |
| Lucide icons | https://github.com/lucide-icons/lucide/blob/c81680e066f45b640743ca78ae36cdedda3f0318/LICENSE |
| crosspoint-simulator `LICENSE` | https://github.com/crosspoint-reader/crosspoint-simulator/blob/84c3421da6f707d6ebe919b3fafca7387ff06464/LICENSE |

Исходники зависимостей, которые PlatformIO скачивает при сборке, в аудит не входили: их лицензии взяты из сводки upstream `licenses/README.md`, а не из самих пакетов (**Needs Verification** по `pio pkg list` первой сборки).

## 1. Главный вывод

| # | Вывод | Статус |
|---|---|---|
| L1 | Собственный код CrossPoint — **MIT** | Confirmed (прочитан `LICENSE`) |
| L2 | **Собранная прошивка (бинарник) распространяется как GPLv3**, потому что включает wolfSSL (GPL-2.0-or-later, CrossPoint выбирает GPLv3) | Confirmed (так написано в `licenses/README.md` upstream) |
| L3 | Наш код в форке можно лицензировать под MIT. Но **любое распространение `firmware.bin`** (релиз на GitHub, передача другому человеку) обязывает дать Corresponding Source под GPLv3: исходники форка, ревизию SDK, скрипты сборки, лицензионные уведомления | Assumption (наша трактовка GPLv3, не юр. совет) |
| L4 | Личное использование без распространения бинарника обязательств GPLv3 не создаёт | Assumption (общая практика GPL; не юр. совет) |
| L5 | **PiccoLink (Android) — отдельная программа**, общается с прошивкой по HTTP; GPL прошивки на него не распространяется. Можно выбрать любую лицензию | Assumption (общепринятая трактовка «arm's length» связи; не юр. совет) |
| L6 | Bookerly в upstream **нет** (опасение из Audit v0.1 снято) | Confirmed (`licenses/fonts.txt`) |

## 2. Компоненты прошивки

| Компонент | Лицензия | Где | Риск для нас |
|---|---|---|---|
| CrossPoint | MIT | `LICENSE` | Нет; сохранять copyright notice |
| FreeInk SDK | MIT (+ отдельные лицензии third-party внутри) | `freeink-sdk/LICENSE`, `NOTICE` | Нет |
| wolfSSL / wolfCrypt | GPL-2.0-or-later → GPLv3 | `licenses/README.md` | Определяет лицензию бинарника (L2) |
| Arduino-ESP32, WebSockets | LGPL-2.1-or-later | там же | Совместимо; учтено в GPLv3 бинаре |
| NimBLE-Arduino, PNGdec, JPEGDEC, ESP-IDF | Apache-2.0 | там же | Сохранять NOTICE |
| ArduinoJson, SdFat, QRCode, Expat, miniz | MIT | там же | Нет |
| uzlib | zlib-style | там же | Нет |
| FreeType | FreeType License (FTL) | `freeink-sdk/libs/font/FreeInkFont/third_party/freetype/FTL.TXT` | Требует упоминания в документации |
| stb_truetype | MIT / public domain | там же | Нет |
| Lucide / Feather icons | ISC | `freeink-sdk/libs/assets/Icons/lucide/LICENSE` | Нет |
| Copied code (EPDiy-tools, atomic14 и др.) | MIT и др. | `licenses/borrowed-code.txt` | Сохранять уведомления |

## 3. Шрифты

| Семейство | Лицензия |
|---|---|
| Встроенные UI: Noto Sans, Ubuntu | OFL 1.1 / Ubuntu Font Licence 1.0 |
| SD-каталог: Literata, Libron, Readerly, Newsreader, Merriweather, Lora, Gentium Book Plus, IBM Plex, Bitter, Libre Baskerville, Vollkorn, Inter, Alegreya, Source Code Pro, Atkinson Hyperlegible Next, Lexica Ultralegible, Noto Serif/Sans (+Hebrew, Arabic), Amiri, Pretendard и др. | В основном SIL OFL 1.1 (детали — `licenses/fonts.txt`) |

Ограничение OFL: **Reserved Font Names** — модифицированный шрифт нельзя распространять под зарезервированным именем (например, Libron). Если будем делать свои подмножества шрифтов — переименовывать.

## 4. Данные
| Данные | Лицензия |
|---|---|
| Русские переносы `hyph-ru` (через typst/hypher) | LPPL 1.3c (`licenses/hyphenation.txt`) |
| Остальные паттерны переносов | MIT / LPPL / прочие — по файлу |

## 5. Инструменты и референсы

| Компонент | Лицензия | Как используем |
|---|---|---|
| crosspoint-simulator | MIT | Только для разработки/CI, не входит в прошивку |
| Folio (`guloff/folio-firmware`) | **Не проверена** — в просмотренных материалах лицензия не найдена | Только как UX/протокольный референс; код не копировать до проверки |
| crosspoint-reader-picco (mreza-yousefi) | **Noncommercial** (заявлено автором) | Код не копировать |
| Тестовый корпус PiccoOS | CC0-1.0, документ `tools/corpus/LICENSE-CORPUS.md` (копируется в корпус) | Свободно |
| DejaVu Serif (встроены в `tools/corpus/fonts/`) | Bitstream Vera / DejaVu, текст лицензии `fonts/LICENSE-DejaVu.txt` | Только для растровых надписей на обложках; файлы шрифтов распространяем с лицензией |
| epubcheck | BSD-3-Clause (W3C) | Инструмент CI |

## 6. Правила для проекта
1. Наш новый код в форке — MIT (как upstream), с заголовком copyright PiccoOS.
2. Не копировать код из Folio и crosspoint-reader-picco.
3. CI по умолчанию **не публикует** `firmware.bin`. Публикация только вручную (`workflow_dispatch`, `publish_firmware=true`) и только комплектом: `firmware.bin`, `LICENSE`, `licenses/`, `PINS.md`, `SOURCE.txt` (репозиторий + commit + submodules), `pio-pkg-list.txt`. Исходники публичны в том же репозитории на том же коммите (GPLv3 §6(d)). Перед первой такой публикацией — проверить, что форк публичный и коммит запушен (D-022).
4. Название: не использовать «BOOX»/«Onyx» в имени продукта и иконках (товарные знаки). «for BOOX Picco» в описании — допустимо как указание совместимости (Assumption, не юр. совет).
5. PiccoLink — выбрать лицензию до первого публичного релиза (рекомендация: Apache-2.0 или MIT).
