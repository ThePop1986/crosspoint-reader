# PiccoOS — Pinned revisions

Обновлено 2026-11-12 (после внешнего ревью). Смена любого пина — отдельный коммит + запись в Decision Log.
Проверка: `piccoos/tools/verify_pins.sh` (запускается в CI job `pins`; можно запустить локально).

## Что считаем воспроизводимым (честные границы)

| Уровень | Статус |
|---|---|
| Исходники (upstream, SDK, simulator) | **Закреплены точно** по commit SHA и проверяются `verify_pins.sh` |
| GitHub Actions | **Закреплены точно** по SHA; скрипт сверяет SHA с точным релизным тегом (сдвиг основного тега — только INFO) |
| Тестовые инструменты (Pillow, epubcheck) | **Закреплены точно**; epubcheck проверяется по sha256 |
| Тестовый корпус | Побайтно одинаков при том же seed, Pillow 12.3.0 и встроенных шрифтах — **проверено на Linux**. Совпадение на macOS/Windows — **Needs Verification** (сравнить с sha256 в `manifest.json`) |
| Python-инструменты сборки (PlatformIO core и зависимости) | Core — точная версия; зависимости — **диапазоны, как в upstream CI**. Каждая сборка **записывает** фактические версии (`pip-freeze.txt`, `penv-freeze.txt`) в artifact `piccoos-env-*` |
| Пакеты PlatformIO (toolchain, framework, `platform = native`) | Задаются platform `55.03.311` / не закреплены для `native`. Каждая сборка **записывает** `pio pkg list`. Закрепить по результатам первой зелёной сборки |
| Образ runner `ubuntu-24.04` | Обновляется GitHub; не закрепляется |

Итог: пока это **прослеживаемые** сборки (всё, что не закреплено, записывается), а не полностью воспроизводимые. Полная воспроизводимость — после первой зелёной сборки: перевести записанные версии в constraints-файл.

## Исходники

| Компонент | Ревизия |
|---|---|
| CrossPoint firmware (upstream base, = `ThePop1986/crosspoint-reader` `piccoos-dev` на 2026-11-12) | `3a5bfac375c293cb38f7e6e28f7736e7d451ef57` |
| FreeInk SDK (submodule `freeink-sdk`) | `6a208c0c46cce99bafa334bc4f171f5e558c5195` |
| Lucide icons (submodule в SDK) | `c81680e066f45b640743ca78ae36cdedda3f0318` |
| CrossPoint simulator | `84c3421da6f707d6ebe919b3fafca7387ff06464` (в `piccoos/sim/platformio.sim.*.ini`) |

## Toolchain (upstream `platformio.ini` / `ci.yml` на базовом коммите)

| Компонент | Версия |
|---|---|
| Platform | `pioarduino/platform-espressif32` `55.03.311` |
| PlatformIO Core | pioarduino `v6.1.19` (и внутри platform penv — upstream workaround) |
| Python (CI) | 3.13 |
| Board (env `picco`) | `esp32-s3-devkitc1-n16r8`, `dio_opi`, `partitions_picco.csv` |
| Simulator lib_deps | ArduinoJson 7.4.2, QRCode 0.0.1 (было `^0.0.1`), WebSockets 2.7.3, AnimatedGIF@`d01888f…` |
| Simulator platform | `native@1.2.1` (закреплено по записи CI на `c6372a68`) |
| Записано CI на `c6372a68` (env `picco`) | framework-arduinoespressif32 3.3.11, libs 5.5.5+sha.b774170ff46, toolchain-xtensa-esp-elf 14.2.0+20260121, esptoolpy 5.3.0; SDL2 2.30.0 (runner) |

## GitHub Actions

| Action | Tag | SHA |
|---|---|---|
| actions/checkout | v6.1.0 | `d23441a48e516b6c34aea4fa41551a30e30af803` |
| actions/setup-python | v6.3.0 | `ece7cb06caefa5fff74198d8649806c4678c61a1` |
| actions/setup-java | v5.7.0 | `b6effb05e454b25005698d916606bdc6ffcbf961` |
| actions/upload-artifact | v6.0.0 | `b7c566a772e6b6bfb58ed0dc250532a479d7789f` |
| actions/download-artifact | v6.0.0 | `018cc2cf5baa6db3ef3c5f8a56943fffe632ef53` |
| actions/cache | v4.3.0 | `0057852bfaa89a56745cba8c7296529d2fc39830` |
| astral-sh/setup-uv | v7.6.0 | `37802adc94f370d6bfd71619e3f0bf239e1f3b78` |

## Тестовые инструменты

| Компонент | Версия / контроль |
|---|---|
| Python для генератора | 3.10+ (Pillow 12 требует ≥ 3.10) |
| Pillow | 12.3.0 |
| epubcheck | 5.2.1, zip sha256 `0532f6291faa2bb729dd253f958868a2a57dbd2c32f881a97c7c980c5940309e` |
| Java | Temurin 21 |
| Шрифты обложек | DejaVu Serif (встроены в `piccoos/tools/corpus/fonts`, sha256 в `manifest.json`) |
| Корпус | `--seed 20261112`; sha256 списка `sha256sum books/*` на Linux: `50020bad6833c422…` |
