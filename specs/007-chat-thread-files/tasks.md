---
description: "Task list — Этап M4 (Лента чата и файлы)"
---

# Tasks: Экраны этапа M4 — Лента чата и файлы

**Input**: Design documents from `specs/007-chat-thread-files/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/{navigation,widgets}.md, quickstart.md

**Tests**: ВКЛЮЧЕНЫ — FR-007 и DoD экрана (roadmap §5) требуют widget + golden (light/dark) на каждый экран/виджет, `bloc_test` на BLoC, unit на форматтер.

**Organization**: задачи сгруппированы по user stories (US1 = 5.2 Chat thread / P1 / MVP; US2 = 5.3 File view / P2; US3 = 5.4 Chat card / P3) для независимой реализации и проверки.

## Format: `[ID] [P?] [Story?] Описание + путь`

- **[P]**: можно параллелить (разные файлы, нет незавершённых зависимостей).
- **[Story]**: метка user story (US1/US2/US3) — только для фаз историй.
- Все пути — от корня репозитория. Команды — через `fvm`/`make` (см. `quickstart.md`).

## Path Conventions

Single Dart package `nox_app`, Clean Architecture слоями-папками: `lib/domain/`, `lib/data/`, `lib/presentation/`, `lib/general/`; тесты deep-mirror под `test/`. Codegen — `make generate` (freezed + injectable, один прогон). Формат — `fvm dart format -l 140 <paths>`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: общая инфраструктура M4 до доменных моделей и экранов.

- [ ] T001 Добавить ≈22 EN-микрокопии M4 (5.2/5.3/5.4) в `lib/general/text_constants.dart` по `contracts/widgets.md` (`tooltipRetry`, `threadEmptyTitle`/`threadEmptyMessage`, `systemChatCreated`, `dateToday`/`dateYesterday`, `tooltipChatInfo`, `tooltipSave`, `savedToDownloads`, `fileDownloadError`, `actionDownload`, `downloadingProgress`, `filesSectionTitle`, `filesViewList`/`filesViewGrid`, `filesEmptyTitle`/`filesEmptyMessage`, `chatInfoTitle`, `chatInfoLoadError`); reuse существующих (`composerHint`/`tooltipSend`/`tooltipAttachFile`/`tooltipRemove`/`tooltipBack`/`noConnection`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: продвижение enum'ов в `domain`, общий вложение-домен и форматтер размера — нужны ВСЕМ трём историям.

**⚠️ CRITICAL**: до завершения этой фазы работа по US1/US2/US3 не начинается.

- [ ] T002 [P] Продвинуть enum `MessageStatus {none,pending,sent,error}` → `lib/domain/model/chat/message_status.dart`; обновить импорт в `lib/presentation/widgets/chat/app_message_bubble_widget.dart` (рендер не менять).
- [ ] T003 [P] Продвинуть enum `FileType {image…other}` → `lib/domain/model/file/file_type.dart`; оставить мапперы `noxFileIcon`/`noxFileColor` в `lib/presentation/widgets/primitives/file_type.dart` (импортируют domain-enum); обновить импорты в `lib/presentation/widgets/chat/app_file_chip_widget.dart`, `lib/presentation/widgets/primitives/app_file_glyph_widget.dart`.
- [ ] T004 Обновить импорты продвинутых enum'ов в `lib/presentation/pages/ui_kit_page/ui_kit_page.dart` и затронутых тестах (`test/presentation/widgets/chat/app_message_bubble_widget_test.dart` + `_golden_test`, `app_file_chip_widget_test`/`_golden_test`, `test/presentation/widgets/primitives/app_file_glyph_widget_test`/`_golden_test`, `file_type_test.dart`, `accessibility_test.dart`) — зависит от T002, T003.
- [ ] T005 [P] Создать `@freezed MessageAttachment` (id, type:`FileType`, name, sizeBytes:int) в `lib/domain/model/chat/message_attachment.dart` — зависит от T003.
- [ ] T006 [P] Создать `FileSizeFormatter` (static `format(int bytes)` → B/KB/MB/GB через `intl NumberFormat`) в `lib/general/formatters/file_size_formatter.dart`.
- [ ] T007 [P] Unit-тест границ `FileSizeFormatter` (0 B / <1 KB / KB / MB / GB) в `test/general/formatters/file_size_formatter_test.dart`.
- [ ] T008 Прогнать `make generate` (freezed для `MessageAttachment`) и убедиться, что `make analyze` чист — зависит от T005.

**Checkpoint**: фундамент готов — истории US1/US2/US3 можно вести (US2 параллельно US1; US3 после фундамента, с кросс-связями к US1/US2).

---

## Phase 3: User Story 1 — Лента чата (5.2 Chat thread, P1) 🎯 MVP

**Goal**: реальная лента сообщений — просмотр истории (группировка по автору, date-separator'ы, system-line), отправка текста/файла с optimistic send, auto-подгрузка старых; снятие последней заглушки M3 (5.1 → реальная 5.2).

**Independent Test**: открыть 5.2 из 5.1 (мобайл push / десктоп thread-pane) и standalone из Галереи; debug-переключателем воспроизвести Initial-loading / Empty / Filled / Loading-older / Sending / Send-error / Offline / Fatal; отправить текст и (no-op) вложение → `pending`→`sent`; retry на `error`.

### Домен/данные (messages-вертикаль)

- [ ] T009 [P] [US1] Создать `IdentityMockData {currentUserId, currentLabel}` в `lib/general/mock/identity_mock_data.dart`.
- [ ] T010 [P] [US1] Создать `@freezed GetMessagesConfig` (chatId, page; `firstPage`/`nextPage`; `pageSize`/`defaultPage`) в `lib/domain/repository/chat/get_messages_config.dart`.
- [ ] T011 [US1] Создать `@freezed MessageModel` (id, chatId, authorId, authorLabel, text?, attachment?:`MessageAttachment`, sentAt:`DateTime`, status:`MessageStatus`, isSystem) в `lib/domain/model/chat/message_model.dart` — зависит от T005, T002.
- [ ] T012 [US1] Создать интерфейс `MessageRepository` (`getMessages`, `sendMessage`, `clean`) в `lib/domain/repository/chat/message_repository.dart` — зависит от T010, T011.
- [ ] T013 [US1] Создать мок-`GetMessagesApi` (`@lazySingleton`): детерминированная история per chatId (own/other по `IdentityMockData.currentUserId`, group-by-author, ранний system-line, пагинация старых наверх + `PageMetadata`; один chatId → пусто) в `lib/data/remote/api/chat/get_messages_api.dart` — зависит от T009, T010, T011.
- [ ] T014 [P] [US1] Создать мок-`SendMessageApi` (`@lazySingleton`): echo `sent` после задержки; debug-исход `error` в `lib/data/remote/api/chat/send_message_api.dart` — зависит от T011.
- [ ] T015 [US1] Создать `MessageRepositoryImpl` (`@LazySingleton(as: MessageRepository, env:[dev,prod,test])`, `BaseRepositoryHelper.execute`) в `lib/data/repository/chat/message_repository_impl.dart` — зависит от T012, T013, T014.
- [ ] T016 [US1] Прогнать `make generate` (freezed `MessageModel`/`GetMessagesConfig` + injectable `MessageRepositoryImpl`) — зависит от T011, T015.

### BLoC

- [ ] T017 [US1] Создать `ChatThreadState` (`@freezed sealed` Initializing / Initialized(pagingState, outgoing, currentId, draftAttachment?, isOffline, loadingInProgress) / Error) + computed-getters (extension: `items`, `composedStream`, `sendActive`, `hasDraft`) в `lib/presentation/pages/chat_thread_page/bloc/chat_thread_state.dart`.
- [ ] T018 [US1] Создать `ChatThreadEvent` (initialize(chatId) / loadOlder / messageSent(text?,attachment?) / sendRetried(localId) / attachmentPicked / attachmentRemoved / setScenario) в `lib/presentation/pages/chat_thread_page/bloc/chat_thread_event.dart`.
- [ ] T019 [US1] Создать `ChatThreadBloc` (sealed, зеркалит `ItemListBloc`: `sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`; optimistic `outgoing`; `getIt<MessageRepository>`; `setScenario` debug) в `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart` — зависит от T017, T018, T012.
- [ ] T020 [US1] Прогнать `make generate` (freezed состояние BLoC) — зависит от T017.

### Виджеты ленты

- [ ] T021 [US1] Апгрейд `AppComposerWidget` → редактируемый (`TextEditingController` + `FocusNode` + `onChanged` + `onSubmitted`, растущий `TextField` maxLines 4–6) в `lib/presentation/widgets/chat/app_composer_widget.dart`; обновить использование в `ui_kit_page.dart` + 3 теста (`app_composer_widget_test.dart`/`_golden_test`, `accessibility_test.dart`).
- [ ] T022 [P] [US1] Создать `AppDateSeparatorWidget` (капсула Today/Yesterday/d MMM) в `lib/presentation/widgets/chat/app_date_separator_widget.dart`.
- [ ] T023 [P] [US1] Создать `AppAuthorHeaderWidget` (label автора над группой чужих) в `lib/presentation/widgets/chat/app_author_header_widget.dart`.
- [ ] T024 [P] [US1] Создать `AppSystemLineWidget` (`Chat created by {username}`) в `lib/presentation/widgets/chat/app_system_line_widget.dart`.
- [ ] T025 [US1] Добавить date-separator-хелпер в `DateFormatter` (Today/Yesterday/`d MMM`) в `lib/general/formatters/date_formatter.dart`.
- [ ] T026 [US1] Создать `AppThreadHeaderWidget` (десктоп: аватар + имя(tap→onInfo) + info `NoxIcons.folderOpen`→onInfo; реконсилирован под NOX — без members/search/folder) в `lib/presentation/widgets/chat/app_thread_header_widget.dart`.
- [ ] T027 [US1] Создать `AppThreadViewWidget` (общий body: обратный `PagedListView` bubbles + date-sep + author-header + system-line + Loading-older + composer; offline `MaterialBanner`; владеет `ChatThreadBloc`; `showHeader` для десктопа) в `lib/presentation/widgets/chat/app_thread_view_widget.dart` — зависит от T019, T021, T022, T023, T024, T025, T026.
- [ ] T028 [US1] Создать `ChatThreadPage` (мобайл `Scaffold(AppBar back + name, resizeToAvoidBottomInset)` + `AppThreadViewWidget`; `route(ChatModel)`/`routeDemo()`; name-tap → TODO(US3 showChatCard)) в `lib/presentation/pages/chat_thread_page/chat_thread_page.dart` — зависит от T027.

### Композиция + Галерея

- [ ] T029 [US1] Снять M3-плейсхолдер в `lib/presentation/pages/chats_list_page/chats_list_page.dart`: `_onTapChat` (мобайл) → `ChatThreadPage.route(chat)` (вместо `RoutePlaceholderPage`); `_threadPane` (десктоп, выбран чат) → `AppThreadViewWidget(chat, showHeader: true)` keyed by chatId (вместо `AppDetailEmptyWidget(comingSoon)`); no-selection placeholder сохранить — зависит от T028, T027.
- [ ] T030 [US1] Обновить M3-тесты 5.1 под реальную ленту (мобайл тап → `ChatThreadPage`; десктоп выбор → `AppThreadViewWidget`) в `test/presentation/pages/chats_list_page/` — зависит от T029.
- [ ] T031 [US1] Активировать строку Галереи 5.2 (`route: ChatThreadPage.routeDemo`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` — зависит от T028.

### Тесты US1

- [ ] T032 [P] [US1] `bloc_test` `ChatThreadBloc` (пагинация старых; optimistic `pending→sent`; `error`+retry; offline; bare-имена состояний; `Error` только при `onError`) против test-env DI в `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart` — зависит от T019.
- [ ] T033 [P] [US1] widget + golden (light/dark, состояния, мобайл/десктоп) `ChatThreadPage`/`AppThreadViewWidget` в `test/presentation/pages/chat_thread_page/` (`settle: false` для Loading-older) — зависит от T028.
- [ ] T034 [P] [US1] widget + golden новых виджетов (`AppComposerWidget` editable, `AppDateSeparatorWidget`, `AppAuthorHeaderWidget`, `AppSystemLineWidget`, `AppThreadHeaderWidget`) в `test/presentation/widgets/chat/` — зависит от T021–T026.

**Checkpoint US1 (MVP)**: лента реальна, стек 5.1→5.2 связан, все состояния воспроизводимы; `make gate` зелёный для US1-области.

---

## Phase 4: User Story 2 — Просмотр файла (5.3 File view, P2)

**Goal**: экран файла-вложения (крупный глиф + имя + размер), auto-скачивание с фейк-прогрессом, сохранение в Downloads (no-op); цель тапа по файлу из 5.2/5.4.

**Independent Test**: открыть 5.3 standalone из Галереи и из 5.2 (тап на file-chip); debug — Loading (определённый %) / Loaded / Inline-error / Fatal; `Save` → snackbar `Saved to Downloads`; десктоп — lightbox 520.

- [ ] T035 [US2] Создать `FileViewPage` (`StatefulWidget` БЕЗ BLoC; локальный таймер-фейк прогресс): мобайл `Scaffold(AppBar back + name(ellipsis) + Save)` + центр column (`AppFileGlyphWidget` крупный + name + size via `FileSizeFormatter`) + `LinearProgressIndicator`(Loading); `Save`→no-op+snackbar; `route(MessageAttachment)`/`routeDemo()` в `lib/presentation/pages/file_view_page/file_view_page.dart` — зависит от T005, T006.
- [ ] T036 [US2] Добавить адаптивный `showFileView(context, attachment)` (мобайл push / десктоп `showDialog` lightbox 520: header глиф+name+download+close, `Download`/`Downloading… {n}%`) в `file_view_page.dart` — зависит от T035.
- [ ] T037 [US2] Подключить тап по file-chip в сообщении → `showFileView` в `AppThreadViewWidget`/bubble (`lib/presentation/widgets/chat/app_thread_view_widget.dart`) — зависит от T036, T027.
- [ ] T038 [US2] Активировать строку Галереи 5.3 (`route: FileViewPage.routeDemo`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` — зависит от T035.
- [ ] T039 [P] [US2] widget + golden `FileViewPage` (Loading %/Loaded; мобайл/десктоп lightbox; `settle: false` для прогресса) в `test/presentation/pages/file_view_page/` — зависит от T035.

**Checkpoint US2**: файловый поток замкнут (5.2/5.4 → 5.3); адаптив push ↔ lightbox.

---

## Phase 5: User Story 3 — Карточка чата (5.4 Chat card, P3)

**Goal**: read-only карточка (имя чата + вложения List/Grid); цель тапа по имени/info из 5.2; файл → 5.3. Завершает Галерею (17/17).

**Independent Test**: открыть 5.4 standalone из Галереи и из 5.2 (имя/info); debug — Initial-loading / Loaded-List / Loaded-Grid / Empty-files / Offline / Fatal; десктоп — right side-sheet 380; файл → 5.3.

### Домен/данные (chat-files)

- [ ] T040 [US3] Добавить `getChatFiles({required String chatId}) → RepositoryResult<List<MessageAttachment>>` в интерфейс `ChatRepository` (`lib/domain/repository/chat/chat_repository.dart`) — зависит от T005.
- [ ] T041 [US3] Создать мок-`GetChatFilesApi` (`@lazySingleton`): список вложений per chatId (varied types/sizes + длинное имя; один chatId → пусто) в `lib/data/remote/api/chat/get_chat_files_api.dart` — зависит от T005.
- [ ] T042 [US3] Реализовать `getChatFiles` в `ChatRepositoryImpl` через `GetChatFilesApi` в `lib/data/repository/chat/chat_repository_impl.dart` — зависит от T040, T041.
- [ ] T043 [US3] Прогнать `make generate` (injectable для `GetChatFilesApi`) — зависит от T041, T042.

### BLoC + виджеты

- [ ] T044 [US3] Создать `ChatCardState` (`@freezed sealed` Initializing / Initialized(files, viewMode, isOffline) / Error) + enum `FilesViewMode {list, grid}` + `ChatCardEvent` (initialize/viewModeChanged/setScenario) в `lib/presentation/pages/chat_card_page/bloc/`.
- [ ] T045 [US3] Создать `ChatCardBloc` (sealed; `getIt<ChatRepository>().getChatFiles`; `executeLogic(onError:)`) в `lib/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart` — зависит от T044, T040.
- [ ] T046 [US3] Прогнать `make generate` (freezed состояние BLoC) — зависит от T044.
- [ ] T047 [P] [US3] Создать `AppSideSheetWidget`/`showRightSideSheet` (десктоп правый side-sheet 380 + scrim через `showGeneralDialog`, slide-in справа) в `lib/presentation/widgets/shell/app_side_sheet_widget.dart`.
- [ ] T048 [US3] Создать `ChatCardPage` (мобайл `Scaffold(AppBar back + name)` + header(аватар 56 + имя) + секция `Files` List/Grid через `AppSegmentedWidget` + Empty `folderOpen`) + адаптивный `showChatCard(context, chat)` (мобайл push / десктоп side-sheet) + `route(ChatModel)`/`routeDemo()` в `lib/presentation/pages/chat_card_page/chat_card_page.dart` — зависит от T045, T047, T006.
- [ ] T049 [US3] Подключить тап по файлу (List/Grid) → `showFileView` (5.3) в `ChatCardPage` — зависит от T048, T036.
- [ ] T050 [US3] Подключить имя (мобайл AppBar 5.2) / info-действие (десктоп `AppThreadHeaderWidget`) → `showChatCard` в `ChatThreadPage`/`AppThreadHeaderWidget` — зависит от T048, T026, T028.
- [ ] T051 [US3] Активировать строку Галереи 5.4 (`route: ChatCardPage.routeDemo`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` — зависит от T048.

### Тесты US3

- [ ] T052 [P] [US3] `bloc_test` `ChatCardBloc` (Loaded list/grid; Empty; viewMode-свитч; offline/error; bare-состояния) в `test/presentation/pages/chat_card_page/bloc/chat_card_bloc_test.dart` — зависит от T045.
- [ ] T053 [P] [US3] widget + golden `ChatCardPage` (List/Grid/Empty; мобайл/десктоп side-sheet) в `test/presentation/pages/chat_card_page/` — зависит от T048.
- [ ] T054 [P] [US3] widget-тест `AppSideSheetWidget` в `test/presentation/widgets/shell/app_side_sheet_widget_test.dart` — зависит от T047.

**Checkpoint US3**: стек чата полон (5.1→5.2→5.3/5.4); Галерея 17/17.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: реконсиляция доков (Принцип II/III), a11y, гейт, golden-baselines.

- [ ] T055 [P] Обновить `docs/roadmap.md`: отметить 5.2/5.3/5.4 `[x]`, строку «Прогресс фазы 1» → 17/17, реестр §6 (лента-элементы/форматтеры — реализовано).
- [ ] T056 [P] Реконсиляция блюпринта/спек: `docs/blueprints/mobile/05-*` (note: `ChatThreadBloc` — network-only carve-out #2; 5.3 — презентационный карв-аут §5.1); desktop-аддендумы в `docs/design/spec/screens/{chat.md,chat-card.md}` (ThreadHeader под NOX-модель; 5.4 side-sheet) сведены с корпусом `01-chats`/`09-drawer`.
- [ ] T057 [P] Добавить новые виджеты M4 в `test/presentation/widgets/accessibility_test.dart` (composer editable, date-sep, author-header, system-line, thread-header, side-sheet).
- [ ] T058 Подключить `MessageRepository.clean()` (+ existing `ChatRepository.clean()`) в logout-флоу `SettingsRootBloc` (полная очистка локальных мок-данных, Принцип I) в `lib/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart` — опционально, если применимо.
- [ ] T059 Прогнать `make gate` (generate → format → analyze → test, goldens исключены) — зелёный; устранить дрейф.
- [ ] T060 Сгенерировать golden-baselines (`make golden-update FILE=…` для новых тестов) на Apple Silicon/macOS; закоммитить `goldens/*.png`.

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T008)** → истории.
- **Foundational блокирует всё**: enum-продвижение (T002–T004), `MessageAttachment` (T005), `FileSizeFormatter` (T006).
- **US1 (T009–T034)** — MVP; снимает заглушку M3.
- **US2 (T035–T039)** — независим от US1 после фундамента (нужны только T005/T006); кросс-связь T037 (file-chip→5.3) зависит от US1 T027.
- **US3 (T040–T054)** — после фундамента; кросс-связи: T049 (файл→5.3) зависит от US2 T036; T050 (имя/info→5.4) зависит от US1 T026/T028.
- **Polish (T055–T060)** — после нужных историй; T059/T060 — финальные.

### Граф историй
```
Setup → Foundational ─┬─ US1 (5.2) ────┐
                      ├─ US2 (5.3) ──┐  │ (T037: US2←US1)
                      └─ US3 (5.4) ──┴──┘ (T049: US3←US2; T050: US3←US1)
                                         → Polish
```

## Parallel Opportunities

- **Foundational [P]**: T002, T003 параллельно (T004 после обоих); T005, T006, T007 параллельно.
- **US1 [P]**: T009, T010 параллельно; T014 ∥ T013-цепочки; виджеты T022, T023, T024 параллельно; тесты T032, T033, T034 параллельно (после своих impl).
- **US2 [P]**: T039 (тест) параллельно прочим после T035.
- **US3 [P]**: T047 параллельно T040–T046; тесты T052, T053, T054 параллельно.
- **Кросс-история**: после фундамента US1 и US2 можно вести параллельно (US3 — с учётом кросс-связей).

## Implementation Strategy

- **MVP = US1 (5.2 Chat thread)** — головной экран этапа; снятие последней заглушки M3 и связывание стека 5.1→5.2 уже даёт демонстрируемую ценность.
- **Инкременты**: US2 (5.3) замыкает файловый поток; US3 (5.4) завершает Галерею (17/17) и фазу 1.
- **Гейт на каждом checkpoint**: `make gate` зелёный; golden-baselines (`make golden-update`) на Apple Silicon. Все бэкенд-зависимости — заглушки с `// TODO(backend):`.

## Total

**60 задач**: Setup 1 · Foundational 7 · US1 (5.2) 26 · US2 (5.3) 5 · US3 (5.4) 15 · Polish 6.
