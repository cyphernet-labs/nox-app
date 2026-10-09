# Implementation Plan: Данные на диске устройства — зашифрованная база и файлы, ключи «только это устройство», ничего в системных бэкапах

**Branch**: `048-device-data-at-rest` (от `security-rework`, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/048-device-data-at-rest/spec.md`

## Summary

Приложение создаёт случайный ключ локальной базы в системном сейфе с пометкой «только это устройство» (на всех пяти платформах; macOS — связка ключей с защитой данных, для чего macOS-сборка подписывается командой). Шифрование — в Rust-модуле на `ring`: Sembast открывается с кодеком, запечатывающим каждую строку; вложения и копии исходящих — кусками по 64 КиБ, как у сервера, с докачкой 043; картинки расшифровываются в память, видео и «Открыть в…» — во временные копии, которые стираются. Данные переезжают из «Документов» в папку данных приложения и исключаются из системных бэкапов. Ключа нет при существующей базе — стирание и спаривание; временная ошибка сейфа — повтор.

## Technical Context

**Language/Version**: Dart 3.12 (Flutter `3.44.1`); Rust 1.93.1 (`packages/nox_tor`); Swift/Kotlin — короткие правки раннеров (метка «не в бэкап», манифест).

**Primary Dependencies**: `ring` (уже в модуле), `sembast` (`SembastCodec`), `flutter_secure_storage` (опции «только это устройство»), `path_provider`; новых пакетов нет.

**Storage**: Sembast с кодеком в папке данных приложения; файлы — формат версии 1 (куски); ключ — сейф.

**Testing**: Rust — сейф; Dart — кодек, файлы, временные копии, ключ, SC-001, бенч SC-003; голдены 5.3 (ошибка открытия) обеих ширин; прогон на macOS.

**Target Platform**: iOS, Android, macOS, Windows, Linux.

**Project Type**: мобильное + десктопное приложение и нативный модуль; провод не меняется.

**Performance Goals**: открытие списка чатов и треда — не медленнее чем на 20% (SC-003).

**Constraints**: ключи и содержимое не в логах; ни одного открытого файла переписки на диске, кроме временных копий по правилам.

**Scale/Scope**: тысячи сообщений, вложения до 100 MiB.

## Constitution Check

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Данные на устройстве зашифрованы ключом «только это устройство»; ничего в системных бэкапах; выход стирает всё. | ✅ |
| II. Спека | 5.3 — сообщение об ошибке открытия; `overview.md` — превью и временные копии; в том же change-set'е. | ✅ |
| III. Блюпринт | Сейф «только это устройство» и отказ от бэкапов — на всех пяти платформах, без desktop-fallback (macOS — подпись командой); кодек — data-слой; блюпринты 04 и 09 обновляются. | ✅ |
| IV–V | Новые строки — в существующих компонентах; EN + UK. | ✅ |
| VI. Паритет | Ошибка открытия — обе ширины, голдены. | ✅ |
| VII. Контракт | Провод не меняется. | ✅ |

## Project Structure

```text
packages/nox_tor/
├── rust/src/vault.rs                  # НОВОЕ: ключ, seal/open, куски
├── rust/src/lib.rs                    # nox_vault_*
└── lib/vault.dart                     # НОВОЕ: NoxVault

lib/
├── data/local/app_database.dart       # кодек, папка данных приложения
├── data/local/vault_codec.dart        # НОВОЕ
├── data/local/sealed_file.dart        # НОВОЕ: формат файла, поток расшифровки, диапазон
├── data/repository/app/{session_repository_impl,auth_repository_impl,app_state_repository_impl}.dart   # ключ, опции, стирание
├── data/repository/file/file_repository_impl.dart        # кэш и докачка кусками
├── data/local/chat/outbox_copies.dart                    # копии запечатаны
├── data/remote/api_client.dart / file datasource         # загрузка из расшифровывающего потока
├── data/service/file/temp_copies.dart                    # НОВОЕ: временные копии
├── di/register_module.dart                               # опции сейфа
├── presentation/widgets/chat/… (картинки из памяти), pages/file_view_page/ (видео, «Открыть в…», «Сохранить», ошибка)
└── l10n/app_{en,uk}.arb
ios/Runner/AppDelegate.swift, macos/Runner/{AppDelegate.swift,*.entitlements}, macos/Runner.xcodeproj (команда)
android/app/src/main/{AndroidManifest.xml,res/xml/data_extraction_rules.xml}
.github/workflows/compile-check.yml (macOS без подписи)
docs/ — blueprints 04, 09; design/spec/screens/file-view.md, overview.md; CLAUDE.md
```

**Structure Decision**: криптография — в модуле (`vault.rs`), формат и потоки — в `lib/data/local/`; платформенные правки — в раннерах.

## Complexity Tracking

| Отступление | Почему нужно | Почему проще не годится |
|---|---|---|
| macOS-сборка подписывается командой | Связка ключей с защитой данных и «только это устройство» требует группы доступа команды | Старая связка ключей macOS уходит в Time Machine и переносится — против решения 2 и Принципа III |
