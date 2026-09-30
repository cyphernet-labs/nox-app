# Quickstart: проверка фазы 040

## Что нужно на машине

- **Rust.** Тулчейн из `packages/nox_tor/rust/rust-toolchain.toml` (1.93.1 со всеми целями). На свежей машине один раз выполнить `cd packages/nox_tor/rust && rustup show active-toolchain`: два первых запуска хука одновременно сталкиваются при скачивании.
- **Android** — NDK 28.2 (`ndkVersion` проекта).
- **iOS и macOS** — Xcode.
- **Linux** — Rust не нужен: хук там ничего не собирает.

## Гейты

```bash
make gate            # codegen → format → analyze → tests; the first run also builds the Rust crate for macOS (~2.5 min)
make golden-verify   # goldens, including the new indicator states for both widths
make tor-test        # cargo test + dart test for packages/nox_tor
```

Ожидание: всё зелёное. `cargo test` покрывает:
- секрет моста;
- снимок состояния;
- onion-адрес из ключа — тот же вектор RFC 8032, что в 039: `25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid`;
- слой, который ловит «устарел».

## Замер (FR-034) — до встраивания

1. Собрать release:
   - `fvm flutter build apk --release --target-platform android-arm64 --dart-define-from-file=config/stage.json`, затем то же без пакета `nox_tor` (ветка-образец), и сравнить размер APK;
   - `fvm flutter build ios --release --no-codesign` — размер `nox_tor.framework`;
   - `fvm flutter build macos --release` — размер framework в `.app`.
2. Подъём. Запустить `noxd` с Tor (039) и спарить приложение дома, затем перезапустить с `--dart-define=nox.forceTor=true`. Этот ключ работает только в debug-сборке и пропускает прямых кандидатов. Время от запуска до `online(tor)` по логу снимается:
   - холодное — каталоги Tor стёрты;
   - тёплое.
3. Память: RSS процесса до и после `online(tor)` — `ps -o rss` на macOS, `adb shell dumpsys meminfo` на эмуляторе.
4. Записать числа в `research.md`, раздел «Замер». Порог — не больше 25 МБ к размеру загрузки на каждой платформе; иначе остановиться и показать цифры владельцу.

## Сквозные сценарии (macOS, симулятор iOS, эмулятор Android)

`noxd` запущен с Tor; tor из Tor Expert Bundle на macOS подписан ad-hoc.

| # | Действия | Ожидание |
|---|---|---|
| 1 | Спарить дома по claim-ссылке | связь прямая, угол пуст; на сервере у устройства появился ключ доступа — «Devices with access from anywhere» на странице статуса |
| 2 | Перезапустить с `nox.forceTor=true` | угол: `Connecting…` + `Tor`, затем `Tor`; сообщения ходят (US1) |
| 3 | В сценарии 2 снять `forceTor` (переключатель отладочного меню не нужен — перезапуск) | путь прямой, Tor остановлен не позже чем через 10 с (SC-002) |
| 4 | На устройстве A создать приглашение | ссылка версии 2, без пометки «только дома» |
| 5 | Устройство B (`forceTor=true`) открывает ссылку v2 | спаривается через Tor одноразовым ключом, затем подключается своим (US4) |
| 6 | Остановить tor на сервере (`-tor=false`) и создать приглашение | карточка: «This link works only on your home network.» |
| 7 | Выйти из аккаунта | нет ключа доступа, списка адресов и каталогов Tor (SC-007) |
| 8 | Сменить адрес сервера: перезапустить `noxd` на другом адресе | приложение через Tor получает новый список и возвращается на прямой путь, история на месте (US3, SC-003) |

### Как прогнать автоматически

Сценарии 1–4, 7 и 8 на macOS проходит зонд `test/live/tor_live_probe.dart`. Он сам запускает `noxd` с tor на LAN-адресе машины, изображает «вне дома» проверкой прямых адресов, которая ничего не находит, и меряет время:

```bash
(cd client_backend && go build -o /tmp/noxd .)
fvm flutter test test/live/tor_live_probe.dart \
  --dart-define=noxd=/tmp/noxd --dart-define=tor=/path/to/tor \
  --dart-define=host=<LAN-адрес машины> --dart-define=work=/tmp/nox_e2e
```

В конце зонд оставляет `noxd` работать, а в `<work>/invites.txt` — два приглашения версии 2. Они живут 10 минут.

Сценарий 5 на симуляторе и эмуляторе:

```bash
xcrun simctl keychain <SIM> reset   # связка ключей iOS переживает удаление приложения
fvm flutter test integration_test/tor_pairing_test.dart -d <SIM|emulator> \
  --dart-define-from-file=config/stage.json --dart-define=link=<приглашение> --dart-define=nox.forceTor=true
```

Тест в конце печатает `NEXT_INVITE` — свежее приглашение для следующей платформы. Повторный запуск спаренного устройства вне дома проверяет `integration_test/tor_relaunch_test.dart` с тем же ключом `nox.forceTor`.

## Проверки на устройстве (владелец)

Симулятор и эмулятор этого не показывают:

- **iOS, реальное устройство**:
  - первое прямое подключение дома показывает запрос доступа к локальной сети с текстом из `NSLocalNetworkUsageDescription`;
  - после согласия связь прямая;
  - при отказе связь идёт через Tor, а пояснение по нажатию на бейдж говорит, где включить доступ.
- **iOS, фон**: свернуть приложение на 5 минут и вернуться — связь восстанавливается не дольше 5 с дома и 30 с вне дома (SC-010).
- **Мобильная сеть вне дома** (iOS и Android): Wi-Fi выключен, приложение открыто — переписка через Tor за 60 с при первом подъёме и за 30 с при повторных (SC-001).
- **Windows**:
  - `fvm flutter build windows --debug`;
  - запустить и пройти сценарии 1–3;
  - проверить, что загрузка Tor не зависает на 15% (Arti #2726).
