# NOX

**NOX** — защищённый кроссплатформенный мессенджер на Flutter (Dart): сквозное
шифрование обмена текстом и файлами, по образцу Signal, поверх модели открытого
общего пространства.

В настоящий момент репозиторий содержит **скелет приложения** (Feature-001):
слои Clean Architecture, одноуровневый DI, тему Material 3 на дизайн-токенах,
адаптивную по ширине оболочку приложения и пагинированный проверочный harness для `Item`
на мок-данных. **Продуктовых функций пока нет** — harness лишь подтверждает, что слоистый
вертикальный срез компилируется и работает end-to-end.

## Целевые платформы

iOS · Android · macOS · Windows · Linux. **Web вне области применения.**

## Инструментарий

- Flutter `3.44.1`, зафиксирован через [FVM](https://fvm.app) (`.fvmrc`) — запускайте каждую команду через `fvm`.
- Один Dart-пакет: `nox_app` (app id `com.cyphernetlabs.noxapp`, stage `com.cyphernetlabs.noxapp.stage`).
- Codegen в первую очередь: Freezed + json_serializable + injectable + flutter_gen (один прогон `build_runner`).

## Настройка

```bash
fvm install                                                   # the pinned SDK
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs  # freezed / json / injectable / assets
```

## Code-gate

```bash
make gate            # generate → format → analyze → test
```

…или пошагово:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart format -l 140 lib test
fvm flutter analyze   # zero-errors gate
fvm flutter test
```

## Запуск / сборка

Flavor'ы (`stage` / `prod`) задаются на этапе компиляции. На мобильных платформах используется нативный `--flavor`;
у desktop нативного flavor нет, поэтому его конфигурация инжектится из
`config/<flavor>.json` через `--dart-define-from-file`:

```bash
# mobile (iOS / Android)
fvm flutter run --flavor stage --dart-define=app.flavor=stage

# desktop (macOS / Windows / Linux)
fvm flutter run -d macos   --dart-define-from-file=config/stage.json
fvm flutter run -d windows --dart-define-from-file=config/stage.json
fvm flutter run -d linux   --dart-define-from-file=config/stage.json
```

## Дополнительно

- Полная настройка и приёмочный walkthrough — `specs/001-flutter-project-init/quickstart.md`
- Архитектурный blueprint — `docs/patterns/mobile/` (индекс в его `README.md`)
- Руководство для контрибьюторов и агентов — `CLAUDE.md`
