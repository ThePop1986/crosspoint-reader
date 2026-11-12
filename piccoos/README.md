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
| `docs/PiccoOS_Home_Balanced_3.0_Spec.md` | Утверждённое ТЗ Balanced 3.0 (Редакция 1.0 финальная, 2026-11-12) |
| `docs/PiccoOS_Decision_Log.md` | Журнал решений D-001…D-038 + A-02 Closed |

## Что проверено, а что нет (2026-11-12, kit v4.1)
| Проверено | Не проверено |
|---|---|
| `actionlint` для workflow; `bash -n` для скриптов | Сборка `picco` и `simulator_picco` |
| `verify_pins.sh`: 14/14 OK; отрицательный тест (неверный тег) — FAIL, как и должно | Детерминизм корпуса на macOS |
| `capture_screens.sh` на **заглушке** (v3 воспроизводит сбой CI один в один, v4 проходит): относительный путь, пустой кадр, старые кадры, тема не применилась, таймаут сценария и общий, экспериментальный сценарий | |
| Корпус: 60/60 epubcheck 5.2.1, детерминизм на Linux, UTF-8-имена в ZIP (проверено Info-ZIP `unzip`) | |
| **A-02 — Closed.** GitHub Actions run `43202234564`: 5/5 jobs success; 5 PNG 480×800 и `summary.txt` (`required failures: 0`) проверены Claude Code | |
| `home_cover_grid` — COVER_GRID подтверждён визуально; `library` и `library_tap` — корректный результат | |
