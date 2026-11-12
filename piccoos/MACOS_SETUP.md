# PiccoOS — форк и симулятор на macOS

Для существующего форка **`ThePop1986/crosspoint-reader`**, ветка **`piccoos-dev`** (на 2026-11-12 она указывает ровно на `3a5bfac`, SDK `6a208c0` — совпадает с `PINS.md`).

Только компьютер. **Picco не подключаем.** Не используем `-t upload`, `esptool`, веб-флешеры (Decision Log D-007).
Время: ~30–60 минут, большая часть — первая сборка.

---

## Шаг 1. Инструменты
```bash
xcode-select --install          # если уже установлено — сообщит об этом
```
Homebrew — по инструкции https://brew.sh, затем:
```bash
brew install git python@3.13 sdl2
git --version && python3.13 --version && sdl2-config --version
```

## Шаг 2. Настройка Actions в форке (один раз, в браузере)
1. https://github.com/ThePop1986/crosspoint-reader → вкладка **Actions**.
2. Если GitHub спрашивает — **I understand my workflows, go ahead and enable them**.
3. Отключите upstream-релизы: в списке слева откройте `release.yml`, `release_candidate.yml`, `release-fonts.yml` → **…** → **Disable workflow**.

## Шаг 3. Клонирование ветки `piccoos-dev`
```bash
mkdir -p ~/dev && cd ~/dev
git clone --recursive -b piccoos-dev https://github.com/ThePop1986/crosspoint-reader.git piccoos
cd piccoos
git remote add upstream https://github.com/crosspoint-reader/crosspoint-reader.git
git log -1 --format=%H
git -C freeink-sdk rev-parse HEAD
```
Ожидается: `3a5bfac375c293cb38f7e6e28f7736e7d451ef57` и `6a208c0c46cce99bafa334bc4f171f5e558c5195`. Если значения другие — остановитесь и пришлите вывод.

## Шаг 4. Добавить файлы PiccoOS и запустить CI
1. Распакуйте `piccoos-phase0a-kit-v4-final.zip` в корень репозитория (`~/dev/piccoos`). Появятся `piccoos/` и `.github/workflows/piccoos-ci.yml`.
2. Проверьте закреплённые версии (только чтение, нужен интернет):
   ```bash
   chmod +x piccoos/tools/verify_pins.sh piccoos/sim/capture_screens.sh
   piccoos/tools/verify_pins.sh
   ```
   Ожидается `failed checks: 0`.
3. Закоммитьте и отправьте:
   ```bash
   git add piccoos .github/workflows/piccoos-ci.yml
   git commit -m "PiccoOS: Phase 0A kit v4 (CI, corpus, simulator config, docs)"
   git push origin piccoos-dev
   ```
4. GitHub → **Actions** → **PiccoOS CI** запустится сам (push в `piccoos-dev`). Первая сборка — 15–30 минут.
5. Если что-то красное — откройте упавший job и пришлите мне лог шага; артефакты `piccoos-env-*` и `piccoos-sim-screens` сохраняются и при ошибке.

## Шаг 5. PlatformIO в отдельном окружении Python
```bash
cd ~/dev/piccoos
python3.13 -m venv .venv
source .venv/bin/activate
pip install "https://github.com/pioarduino/platformio-core/archive/refs/tags/v6.1.19.zip" "Pillow==12.3.0"
pio --version
```
В каждом новом окне Terminal: `cd ~/dev/piccoos && source .venv/bin/activate`.

## Шаг 6. Включить симулятор (upstream `platformio.ini` не меняется)
```bash
cp piccoos/sim/platformio.sim.macos.ini platformio.local.ini
```
`platformio.local.ini` в `.gitignore` и в git не попадёт.

## Шаг 7. Сборка симулятора
```bash
pio run -e simulator_picco
```
Ожидается `SUCCESS`. При ошибке пришлите последние 40 строк.

## Шаг 8. Тестовые книги — в отдельную папку
Существующие файлы симулятора (`fs_/`) не трогаем. Корпус и «SD-карта» для тестов живут отдельно:
```bash
python3 -I piccoos/tools/corpus/make_corpus.py --out piccoos-corpus
mkdir -p piccoos-sd/books
cp -n piccoos-corpus/books/*.epub piccoos-sd/books/
```
Ожидается `wrote 60 books ... self-check failures: 0`. `cp -n` не перезаписывает существующие файлы. Папки `piccoos-corpus/` и `piccoos-sd/` не коммитим.

## Шаг 9. Запуск
```bash
CROSSPOINT_SIM_SD="$PWD/piccoos-sd" .pio/build/simulator_picco/program
```
| Клавиша | Действие |
|---|---|
| ↑ / ↓ | Кнопки листания Picco |
| Return | Confirm |
| Escape | Back |
| T | Слайд-переключатель |
| Мышь | Касание |

COVER_GRID: Settings → Display (Экран) → UI Theme (Тема интерфейса) → Cover Grid (Сетка обложек).

## Шаг 10. Скриншоты
```bash
HEADLESS=0 piccoos/sim/capture_screens.sh .pio/build/simulator_picco/program piccoos-corpus sim-out
cat sim-out/summary.txt
open sim-out
```
Скрипт сам делает свежую «SD-карту» для каждого сценария во временной папке; ваши папки не меняет.
Обязательные сценарии: `home_lyra`, `home_cover_grid`. `library` — экспериментальный (координаты касания уточним по вашим скриншотам), его ошибка не роняет запуск.

---

## Если что-то пошло не так
| Симптом | Что сделать |
|---|---|
| `sdl2-config: command not found` | `brew install sdl2`, перезапустить Terminal |
| Ошибка про порт 8080 | В `platformio.local.ini` раскомментировать `custom_simulator_http_port = 18080` |
| Симулятор сразу открывает книгу | Удалить `piccoos-sd/.crosspoint/state.json` |
| Ошибки C++ после обновления | `rm -rf .pio` и собрать заново; не помогло — прислать лог |
| Apple Silicon: ошибки архитектуры | `which python3.13` должен указывать в `/opt/homebrew` |

## Чего не делать
- Не подключать Picco по USB.
- Не запускать `pio run -e picco -t upload`, `esptool`, веб-флешеры.
- Не устанавливать никакой `firmware.bin` (по умолчанию CI его и не публикует).
