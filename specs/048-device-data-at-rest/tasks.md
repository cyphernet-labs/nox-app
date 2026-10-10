# Tasks: Данные на диске устройства

**Input**: Design documents from `specs/048-device-data-at-rest/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; 044–047 влиты в `security-rework`

**Tests**: обязательны: Rust, Dart (юнит, виджеты), голдены 5.3 обеих ширин, прогон на macOS.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Сейф в модуле: `packages/nox_tor/rust/src/vault.rs` + `nox_vault_*` в `lib.rs` по `contracts/ffi-vault.md` (ChaCha20-Poly1305 и HKDF на `ring`, ключ в обнуляемом буфере); тесты Rust (круг, чужой ключ, подмена, усечение, последний кусок)
- [x] T002 [P] `packages/nox_tor/lib/vault.dart` (`NoxVault`) и привязки; тест пакета

## Phase 2: Foundational

- [x] T003 Ключ локальной базы и опции «только это устройство»: `lib/di/register_module.dart` (iOS `first_unlock_this_device`, macOS — защита данных, Windows — файл хранилища плагина в `%LOCALAPPDATA%`, а не в перемещаемом профиле, Linux — libsecret), `lib/data/repository/app/session_repository_impl.dart` (`device.storage_key`, ключ устройства), состояние при запуске (`app_state_repository_impl.dart`: нет ключа + есть база — выход; ошибка — повтор), выход — стирание ключей; тесты
- [x] T004 macOS: подпись командой (`macos/Runner.xcodeproj`: `DEVELOPMENT_TEAM`, автоматическая), `keychain-access-groups` в `macos/Runner/{DebugProfile,Release}.entitlements`; `.github/workflows/compile-check.yml` — macOS без подписи (`CODE_SIGNING_ALLOWED=NO`); проверка `flutter build macos` здесь
- [x] T005 Папка данных и бэкапы: корень данных (`getApplicationSupportDirectory()`, Windows — `%LOCALAPPDATA%\NOX`) для базы, вложений и исходящих (`lib/data/local/app_database.dart`, `file_repository_impl.dart`, `outbox_copies.dart`); метка «не в бэкап» на iOS и macOS (`AppDelegate.swift`, метод платформы `nox/backup`); Android — `android:allowBackup="false"`, `fullBackupContent="false"`, `res/xml/data_extraction_rules.xml`; тесты путей

## Phase 3: User Story 1 — на диске нет открытой переписки (P1) 🎯 MVP

- [x] T006 [US1] Кодек Sembast `lib/data/local/vault_codec.dart` (`SembastCodec('nox-vault-1')`), открытие базы с ним; тесты (круг, чужой ключ — отказ подписи)
- [x] T007 [US1] Формат файла `lib/data/local/sealed_file.dart`: запись кусками, поток расшифровки, чтение диапазона, докачка с границы куска; тесты
- [x] T008 [US1] Кэш вложений и докачка 043 на формате (`lib/data/repository/file/file_repository_impl.dart`, `AttachmentDownloadService`), копии исходящих и загрузка из расшифровывающего потока (`outbox_copies.dart`, `FileRemoteDataSource`/`ApiClient.putBytes`); картинки — из памяти (`AppImageAttachmentWidget`, просмотрщик); тесты (докачка с середины куска, загрузка с `received`)
- [x] T009 [US1] Тест SC-001 (`test/data/local/at_rest_test.dart`): наполнить базу и файлы маркерами, искать по папке данных — ноль совпадений

## Phase 4: User Story 2 — ничего в системных бэкапах (P1)

- [x] T010 [US2] Тесты меток «не в бэкап» (iOS/macOS — вызов метода платформы на корне данных), манифеста Android; проверка `tmutil isexcluded` на macOS — вручную по `quickstart.md`

## Phase 5: User Story 3 — видео, «Открыть в…», «Сохранить» (P2)

- [x] T011 [US3] Временные копии `lib/data/service/file/temp_copies.dart`: `<temp>/nox_open`, видео — стереть при закрытии плеера, «Открыть в…» — при следующем запуске или выходе, очистка при запуске; «Сохранить» — расшифровка в выбранное место; ошибка «нет места» (`Couldn't open this file. Free up some space and try again.` EN + UK) на 5.3 (`file_view_page`); тесты; голдены ошибки открытия — mobile + desktop

## Phase 6: User Story 4 — ключ не прочитать и выход (P2)

- [x] T012 [US4] Тесты: ключа нет + база есть — экран спаривания, после спаривания чаты на месте (SC-006); ошибка чтения сейфа — без стирания; выход — пусто в папке данных и сейфе (SC-005)

## Phase 7: Polish & Cross-Cutting

- [x] T013 [P] Бенч SC-003 (`test/data/local/at_rest_bench_test.dart`, тег `live` или отдельная метка): 10 000 сообщений, открытие списка и треда до и после — не больше +20%
- [x] T014 [P] Документы: блюпринты `docs/blueprints/mobile/{04-data-layer,09-build-and-secrets-infra}.md`, `docs/design/spec/screens/file-view.md`, `docs/design/spec/overview.md`, корпуса 5.3 (ошибка открытия), `CLAUDE.md` (хранилище, пути, macOS-подпись)
- [x] T015 Аудит логов: ни ключей, ни содержимого
- [x] T016 Гейты: `make tor-test`, `make gate`, `make golden-verify`
- [x] T017 Прогон на macOS по `quickstart.md` §2; итог — в `research.md`
- [x] T018 Трекер `docs/client-backend/roadmap-security.md`: 048 реализована

## Dependencies & Execution Order

T001 → T002 → T003 → T004, T005 → T006 → T007 → T008 → T009; T010 после T005; T011 после T007; T012 после T003; Polish — в конце.

## Implementation Strategy

MVP — US1 + US2: зашифровано и не уходит в бэкапы. Затем US3 и US4.
