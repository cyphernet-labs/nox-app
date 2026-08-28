# NOX

**NOX** — защищённый кроссплатформенный мессенджер на Flutter (Dart): сквозное
шифрование обмена текстом и файлами, по образцу Signal, поверх модели открытого
общего пространства.

Приложение доведено до полноценного продукта на моках (фичи 001–021): все 17 экранов
собраны, бизнес-логика настоящая — реактивные списки, непрочитанное, оптимистичная
отправка с офлайн-очередью, файловый пикер, превью изображений, l10n EN+UK,
персистентные настройки и сессия; данные живут в реальной локальной Sembast-БД.

Бэкенд выбран, первый этап работает: client-сервер на **Go** со встроенной SQLite
(`client_backend/`, фичи 022–024), проводной **контракт v0**, транспорт — WebSocket
поверх wss:443 с пиннингом. Идёт клиентский трек 025–028: data-слой приложения уже
говорит на языке контракта, но источники данных всё ещё мок-овые — транспорт
подключается в фазе 027, подмена источников — в 028.

Verification-only остаётся только срез `Item` (`AppShell`/`ItemListPage` из Feature-001,
не смонтированы) — он лишь подтверждает, что слоистый вертикальный срез работает
end-to-end.

## Целевые платформы

iOS · Android · macOS · Windows · Linux. **Web вне области применения.**

## Инструментарий

- Flutter `3.44.1`, зафиксирован через [FVM](https://fvm.app) (`.fvmrc`) — запускайте каждую команду через `fvm`.
- Один Dart-пакет: `nox_app`, единый app id `com.cyphernetlabs.noxapp` на всех пяти платформах
  (флейвор — только compile-time define `--dart-define-from-file=config/<flavor>.json`;
  отдельных нативных id и подписи пока нет).
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

Flavor'ы (`stage` / `prod`) задаются на этапе компиляции и инжектятся из
`config/<flavor>.json` через `--dart-define-from-file` единообразно на всех пяти платформах
(нативные mobile-флейворы отложены — у скелета нет per-flavor нативной разницы):

```bash
# mobile (iOS / Android)
fvm flutter run --dart-define-from-file=config/stage.json

# desktop (macOS / Windows / Linux)
fvm flutter run -d macos   --dart-define-from-file=config/stage.json
fvm flutter run -d windows --dart-define-from-file=config/stage.json
fvm flutter run -d linux   --dart-define-from-file=config/stage.json
```

## Дополнительно

- Полная настройка и приёмочный walkthrough — `specs/001-flutter-project-init/quickstart.md`
- Архитектурный blueprint — `docs/blueprints/mobile/` (индекс в его `README.md`)
- Руководство для контрибьюторов и агентов — `CLAUDE.md`
