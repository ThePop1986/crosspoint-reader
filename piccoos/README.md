# piccoos/ — PiccoOS fork additions

Всё, что PiccoOS добавляет к upstream CrossPoint, лежит здесь (плюс `.github/workflows/piccoos-ci.yml`).
Upstream-файлы не меняются, пока нет утверждённой задачи (Spec v0.2 §2.1).

| Путь | Назначение |
|---|---|
| `CHANGELOG.md` | История изменений комплекта |
| `PINS.md` | Закреплённые ревизии и честные границы воспроизводимости |
| `LICENSE_AUDIT.md` | Аудит лицензий (A-03) с постоянными ссылками для проверки |
| `MACOS_SETUP.md` | Форк `ThePop1986/crosspoint-reader` (`piccoos-dev`) + симулятор на macOS |
| `sim/platformio.sim.{linux,macos}.ini` | Env `simulator` + `simulator_picco`; копируется в `platformio.local.ini` |
| `sim/capture_screens.sh` | Headless-скриншоты: обязательные и экспериментальные сценарии, проверка изображений, таймауты |
| `tools/verify_pins.sh` | Независимая проверка всех закреплённых SHA (actions, upstream, SDK, simulator) |
| `tools/corpus/make_corpus.py` | Генератор 60 синтетических EPUB (CC0, встроенные шрифты, фиксированный seed) |
| `tools/corpus/pack_corpus.py` | Упаковка корпуса в ZIP с UTF-8-именами + самопроверка по манифесту |
| `tools/corpus/LICENSE-CORPUS.md`, `tools/corpus/fonts/` | Лицензия корпуса; DejaVu Serif + лицензия |

## Что проверено, а что нет (2026-11-12, kit v4)
| Проверено в среде Claude | Не проверено |
|---|---|
| `actionlint` для workflow; `bash -n` для скриптов | Запуск workflow на GitHub (A-02 не завершена до зелёного CI) |
| `verify_pins.sh`: 14/14 OK; отрицательный тест (неверный тег) — FAIL, как и должно | Сборка `picco` и `simulator_picco` |
| `capture_screens.sh` на **заглушке, повторяющей семантику скриптов симулятора** (v3 воспроизводит сбой CI один в один, v4 проходит, включая `library` и `library_tap`): относительный путь, пустой кадр, старые кадры, тема не применилась, таймаут сценария и общий таймаут, экспериментальный сценарий | Работа скрипта с **реальным** симулятором; что `home_cover_grid` — именно COVER_GRID (проверить глазами) |
| Корпус: 60/60 epubcheck 5.2.1, детерминизм на Linux, UTF-8-имена в ZIP (проверено Info-ZIP `unzip`) | Детерминизм корпуса на macOS |
