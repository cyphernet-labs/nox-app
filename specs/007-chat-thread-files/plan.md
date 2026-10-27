# Implementation Plan: Экраны этапа M4 — Лента чата и файлы

**Branch**: `007-chat-thread-files` | **Date**: 2026-06-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/007-chat-thread-files/spec.md`

## Summary

Реализовать три **самых сложных** экрана детализации чата (последний этап фазы 1) — **Chat thread / Лента чата (5.2)**, **File view / Просмотр файла (5.3)**, **Chat card / Карточка чата (5.4)** — и **снять последнюю заглушку M3** (плейсхолдер ленты): тап по чату в 5.1 (мобайл) и выбор строки в thread-pane (десктоп) ведут на **реальную** ленту; имя/info чата → реальная 5.4; файл-вложение → реальная 5.3. После M4 стек чата (5.1 → 5.2 → 5.3/5.4) полностью связан, фаза 1 завершена (17/17). Бэкенд (реальный транспорт/сервер/файлы) вне scope — данные мок.

Технический подход (по верифицированному коду `lib/`, research-проход 2026-06-21):
- **5.2 `ChatThreadPage` + `ChatThreadBloc`** — **network-only мок-вертикал сообщений** (второй carve-out после списка чатов), зеркалит `ItemListBloc`/`ChatsListBloc`: новые `MessageModel`/`MessageAttachment` (domain) + мок-`GetMessagesApi` (пагинация старых **наверх**) + мок-`SendMessageApi` (one-shot POST) + `MessageRepository`/`Impl` через DI. `ChatThreadBloc` — **sealed** `Initializing/Initialized/Error` + `PagingState`-в-bloc, `transformer: sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`; держит историю (paged) + `outgoing` (optimistic pending/sent/error) + `currentId` + offline. `PagedListView(reverse: true)` (новые внизу). Reuse `AppMessageBubbleWidget` (статусы `schedule`/`check`/`error` уже есть) + новые `AppDateSeparatorWidget`/`AppAuthorHeaderWidget`/`AppSystemLineWidget` + **апгрейд** `AppComposerWidget` (display-only → редактируемый). Десктоп — thread-pane внутри list-detail 5.1 (persistent `AppThreadHeaderWidget`, колонка ≤980).
- **5.3 `FileViewPage`** — **локальный `StatefulWidget` без BLoC** (карв-аут блюпринта 05 §5.1: презентационный экран без репозитория; фейк-прогресс — таймер-драйвен локальное состояние). Reuse `AppFileGlyphWidget` (крупный глиф) + новый **форматтер размера файла**. Мобайл fullscreen (AppBar back + name + `Save`); десктоп lightbox-`Dialog` (~520, `Download`). Адаптивный вход `showFileView(context, attachment)`.
- **5.4 `ChatCardPage` + `ChatCardBloc`** — sealed `Initializing/Initialized/Error` поверх мок-источника файлов чата (метод `ChatRepository.getChatFiles` + мок-`GetChatFilesApi`, **без пагинации**). Reuse `AppAvatarWidget` (header 56), `AppSegmentedWidget` (List/Grid), `AppFileGlyphWidget`/`AppFileChipWidget`, state-виджеты. Мобайл fullscreen (AppBar back + name); десктоп правый **side-sheet 380** со scrim (корпус `09-drawer`) из info-действия ThreadHeader. Адаптивный вход `showChatCard(context, chat)`.

**Новые зависимости не добавляются** (Clarifications): `file_picker`/`file_saver`/`path_provider`/`qr_flutter` — Фаза 2. Attach = no-op picker (синтез `MessageAttachment`); 5.3 download = фейк-прогресс; Save = no-op + snackbar. Размер файла — на уже доступном `intl`. **Новых SVG-иконок не требуется** (все глифы есть: `attachFile`/`sendFill`/`arrowBack`/`download`/`close`/`schedule`/`check`/`error`/`chatBubble`(empty 5.2)/`folderOpen`(empty 5.4 + desktop info-действие)/file-types). Микрокопия EN через `TextConstants` (≈22 новых строк).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned), длина строки 140, стоковый `flutter_lints`.

**Primary Dependencies**: `flutter_bloc` 9.1.1, `bloc_concurrency` 0.3.0 (`sequential()` для пагинации ленты), `freezed` 3.2.5 + `freezed_annotation` (`MessageModel`/`MessageAttachment`/`GetMessagesConfig` + BLoC-состояния), `injectable`+`get_it` (DI для `MessageRepository`, `ChatRepository.getChatFiles`), `infinite_scroll_pagination` v5 (`PagingState`-в-bloc, `PagedListView(reverse: true)` — 5.2 второй потребитель после 5.1), `flutter_screenutil`, `flutter_svg`, `flutter_gen`, `intl` 0.20.2 (форматтер размера файла). **Новые зависимости не добавляются.**

**Storage**: Реальной персистентности нет. Сообщения, вложения и файлы чата — **network-only мок-репозитории** (мок-API синтезируют данные + задержку + `PageMetadata`, как `GetChatsApi`/`GetItemsApi`; без Sembast-кэша — cache-first слой backend-фазы). Кэш скачанного файла (5.3) и сохранение в Downloads — заглушка (in-memory флаг / no-op). BLoC-состояния — in-memory на время жизни страницы.

**Testing**: `flutter_test` + `bloc_test` (для `ChatThreadBloc` sealed-trio + paging + optimistic send, `ChatCardBloc` sealed-trio) + `mockito` (только; mocktail запрещён); golden через локальный харнес `test/utils/golden.dart` (Apple Silicon/macOS, тег `golden`, вне CI). Обязателен `pumpApp`. BLoC-тесты ассертят **bare**-имена сабстейтов (`Initializing`/`Initialized`/`Error`); `Error` эмитится только при переданном `onError`. 5.3 — widget-тест (без BLoC); форматтер размера — unit-тест границ.

**Target Platform**: iOS, Android, Windows, Linux, macOS (web вне scope). Один пакет `nox_app`.

**Project Type**: Кросс-платформенное Flutter-приложение (single package), Clean Architecture слоями-папками. M4 затрагивает **presentation** (3 экрана + 2 BLoC + composer-апгрейд + новые виджеты ленты) + **domain** (`MessageModel`/`MessageAttachment`/`MessageRepository` интерфейс + `ChatRepository.getChatFiles` + продвижение enum'ов `MessageStatus`/`FileType`) + **data** (мок-`GetMessagesApi`/`SendMessageApi`/`GetChatFilesApi` + impl'ы) + **di** (регистрация) + **general** (форматтер размера файла + `IdentityMockData`) + точечно **presentation/pages/chats_list_page** (замена M3-плейсхолдеров) и **screens_gallery** (активация 3 строк).

**Performance Goals**: 60 fps; обратный (`reverse:true`) `PagedListView` с авто-подгрузкой старых (`sequential()`); optimistic send — мгновенная вставка `pending`; фейк-прогресс скачивания на `NoxDuration`/`NoxEasing`; спиннеры на токенах.

**Constraints**: Токен-дисциплина (нет сырых `Color`/`EdgeInsets`/`TextStyle`/overlay-литералов вне `lib/design/theme/`); иконки только SVG `NoxIcons`; микрокопия EN через `TextConstants`; адаптив width-driven по `Constants.railBreakpoint` (840dp) через `LayoutBuilder` (не Platform). **Новых brand-fixed исключений M4 не вводит** (их два: тёмный splash 1.1, светлая QR-поверхность 7.1). Декоративные brand-цвета глифов типов файлов (`noxFileColor`) — уже зафиксированное исключение из `ColorScheme` (Feature-003).

**Scale/Scope**: 3 экрана + 2 BLoC (`ChatThreadBloc` sealed+paging+optimistic, `ChatCardBloc` sealed) + 5.3 BLoC-less + **messages-вертикаль** (`MessageModel`/`MessageAttachment`, `GetMessagesConfig`, мок-`GetMessagesApi`/`SendMessageApi`, `MessageRepository`/`Impl`, DI) + **chat-files** (мок-`GetChatFilesApi` + `ChatRepository.getChatFiles`) + новые виджеты (`AppDateSeparatorWidget`, `AppAuthorHeaderWidget`, `AppSystemLineWidget`, `AppThreadHeaderWidget`, `AppThreadViewWidget` общий body, `AppSideSheetWidget` desktop drawer) + **апгрейд** `AppComposerWidget` (editable) + продвижение enum'ов `MessageStatus`/`FileType` в domain + форматтер размера файла + `IdentityMockData` + замена M3-плейсхолдеров в 5.1 + ≈22 микрокопии + активация 3 строк Галереи. Тесты widget+golden на каждый экран/виджет + bloc_test на 2 BLoC + unit на форматтер + gallery-тест.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Лента показывает **мок**-содержимое; E2EE — транспортный слой (вне scope, бэкенд не выбран). own/other — по **мок**-идентичности (`IdentityMockData`, не реальный идентификатор). Attach/download/save — заглушки (no-op), реальных файлов и сети нет. Нет аналитики/логов с PII/содержимым. Logout-очистка (M3) уже сбрасывает мок-репозитории через `clean()` (расширим на messages/files). |
| **II. Спека/дизайн-корпус — источник истины** | ✅ PASS (с зафиксированными reconciliation) | Строим по locked `docs/design/spec/screens/{chat,file-view,chat-card}.md` + **авторитетному десктоп-корпусу** `nox-desktop-screens/{01-chats,08-file,09-drawer}.md` + мобайл-корпусу + `spec.md`. **Зафиксированные расхождения, разрешаемые осознанно в этом change-set** (Complexity Tracking): (а) **desktop ThreadHeader** реконсилируется под продуктовую модель NOX — только аватар + имя + info(→5.4); `members`/per-chat `search`/`folder` из корпуса `01-chats` = дрейф (нет участников/подписок; per-chat-поиск/папки вне scope); (б) снятие M3-плейсхолдеров ленты (FR-008) — out-of-scope 5.2 закрывается **планово** этим этапом, не «молча». |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS (с reconciliation блюпринта) | Страницы по конвенции (`pages/<page>_page/`, `route()`/`routeDemo()`, токены, `NoxIcons`, `TextConstants`). **`ChatThreadBloc` — network-only carve-out** (второй после 5.1): зеркалит `ItemListBloc` (sealed-trio, `PagingState`-в-bloc, `sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`) поверх `MessageRepository` через `getIt`. **`ChatCardBloc`** — sealed-trio поверх `ChatRepository.getChatFiles` (без пагинации). **5.3 — `StatefulWidget` без BLoC** (карв-аут 05 §5.1: презентационный экран без репозитория/domain-state; фейк-прогресс — локальный). **Reconciliation (Принцип III, тот же change-set):** (1) продвижение `MessageStatus`/`FileType` в `domain` (единый источник, `domain` остаётся import-free; мапперы `noxFileIcon`/`noxFileColor` — в presentation); (2) апгрейд `AppComposerWidget` (display-only → editable) + правка её галереи/тестов; (3) блюпринт 05 §6.5 (desktop = «rail + единый body») уже реконсилирован в M3 под list-detail — 5.2/5.4 desktop встраиваются в эту раскладку. |
| **IV. Верность дизайн-системе** | ✅ PASS | M4 light+dark, только токены. Иконки — SVG `NoxIcons`: все нужные глифы **уже есть** — **новых SVG не требуется** (empty 5.2 = `chatBubble`, empty 5.4 = `folderOpen`, desktop info-действие = `folderOpen`, save/download = `download`, статусы = `schedule`/`check`/`error`, attach/send = `attachFile`/`sendFill`). Никаких новых brand-fixed исключений. Возможные темы стоковых компонентов (`ProgressIndicatorThemeData` для `LinearProgressIndicator` на 5.3) — **тематизация**, не хардкод (добавляется только при необходимости; default `ColorScheme` приемлем). |
| **V. Языковая дисциплина** | ✅ PASS | Спека/план — RU; код/идентификаторы/коммиты — EN; UI-микрокопия — EN (`TextConstants`, ≈22 новых строк); RU в UI отсутствует. |

**Gate (до Phase 0): PASS.** Нарушений-блокеров нет. Reconciliation-пункты (desktop ThreadHeader scope; продвижение enum'ов; апгрейд composer) — осознанные, в этом же change-set (Complexity Tracking). Введение `ChatThreadBloc`/`ChatCardBloc` и messages-вертикали — следование блюпринту (network-only carve-out), не усложнение.

**Re-check (после Phase 1 design): PASS.** Design-артефакты не вводят новых зависимостей. `ChatThreadBloc` (sealed + `PagingState` + optimistic `outgoing`) и `ChatCardBloc` (sealed) согласованы с блюпринтом 05. Optimistic send — view-state списка (мгновенная вставка + статус-переход), не nav-side-effect. `domain` остаётся import-free после продвижения enum'ов (чистые leaf-типы). Десктоп thread-pane/side-sheet встраиваются в M3 list-detail. Спека↔корпус↔блюпринт↔код приводятся к консистентности в этом change-set (Принцип II/III). Готово к `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/007-chat-thread-files/
├── plan.md              # Этот файл (/speckit-plan)
├── research.md          # Phase 0 — технические решения (verified против lib/)
├── data-model.md        # Phase 1 — messages/files-вертикаль + BLoC-состояния/энумы/визуальный вокабуляр
├── quickstart.md        # Phase 1 — как запустить и проверить
├── contracts/           # Phase 1 — UI-контракты
│   ├── navigation.md     #   route()/routeDemo(), активация Галереи, снятие M3-плейсхолдеров, композиция стека чата
│   └── widgets.md        #   публичные API новых/изменённых виджетов + BLoC event/state + форматтер + enum-продвижение
├── checklists/
│   └── requirements.md  # из /speckit-specify + /speckit-clarify (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этим планом)
```

### Source Code (repository root)

```text
lib/domain/
├── model/chat/message_model.dart            # NEW @freezed MessageModel{id, chatId, authorId, authorLabel, text?, attachment?(MessageAttachment), sentAt(DateTime), status(MessageStatus), isSystem}
├── model/chat/message_attachment.dart       # NEW @freezed MessageAttachment{id, type(FileType), name, sizeBytes(int)}
├── model/chat/message_status.dart           # NEW (PROMOTED) enum MessageStatus {none, pending, sent, error} — единый источник
├── model/file/file_type.dart                # NEW (PROMOTED) enum FileType {image,video,audio,pdf,doc,sheet,text,archive,other} — единый источник
├── repository/chat/message_repository.dart  # NEW interface: getMessages(GetMessagesConfig) + sendMessage(chatId, text?, attachment?) + clean()
├── repository/chat/get_messages_config.dart # NEW @freezed {chatId, page} (зеркалит GetChatsConfig)
└── repository/chat/chat_repository.dart     # EDIT: + getChatFiles({required String chatId}) (chat-owned files, без пагинации)

lib/data/
├── remote/api/chat/get_messages_api.dart    # NEW @lazySingleton мок: детерминированная история per chatId (своя/чужие по IdentityMockData.currentUserId, group-by-author, system-line), пагинация старых наверх + PageMetadata
├── remote/api/chat/send_message_api.dart    # NEW @lazySingleton мок: one-shot POST → echo (sent) после задержки; debug-исход error
├── remote/api/chat/get_chat_files_api.dart  # NEW @lazySingleton мок: список вложений per chatId (varied types/sizes; пустой набор для одного чата)
├── repository/chat/message_repository_impl.dart       # NEW @LazySingleton(as: MessageRepository, env:[dev,prod,test]) → RepositoryResult
└── repository/chat/chat_repository_impl.dart          # EDIT: реализовать getChatFiles via GetChatFilesApi; clean() — no-op (как сейчас)

lib/presentation/pages/
├── chat_thread_page/
│   ├── chat_thread_page.dart                 # NEW: мобайл Scaffold(AppBar back + name→5.4, resizeToAvoidBottomInset) + AppThreadViewWidget; route()/routeDemo(); ХОСТИТ AppThreadViewWidget (владелец ChatThreadBloc — единый владелец для мобайл-страницы и десктоп thread-pane)
│   └── bloc/
│       ├── chat_thread_bloc.dart             # NEW (sealed, зеркалит ItemListBloc): sequential(), executeLogic(onError:), applyPage; getIt<MessageRepository>; optimistic send/retry
│       ├── chat_thread_event.dart            # initialize(chatId) / loadOlder / messageSent(text?,attachment?) / sendRetried(localId) / attachmentPicked / attachmentRemoved / setScenario(debug)
│       └── chat_thread_state.dart            # @freezed sealed: Initializing / Initialized(pagingState, outgoing, currentId, draftAttachment?, isOffline, isSending) / Error
├── file_view_page/
│   └── file_view_page.dart                   # NEW: StatefulWidget БЕЗ BLoC (локальный download-progress, таймер-фейк). мобайл Scaffold(AppBar back+name+Save) ; адаптивный showFileView() → десктоп lightbox Dialog (~520). route()/routeDemo()
└── chat_card_page/
    ├── chat_card_page.dart                    # NEW: мобайл Scaffold(AppBar back+name) header(avatar 56)+Files(List/Grid); владеет ChatCardBloc; route()/routeDemo()
    └── bloc/
        ├── chat_card_bloc.dart               # NEW (sealed): getIt<ChatRepository>().getChatFiles(chatId) внутри executeLogic(onError:); держит files + viewMode(list/grid)
        ├── chat_card_event.dart              # initialize(chatId) / viewModeChanged(FilesViewMode) / setScenario(debug)
        └── chat_card_state.dart              # @freezed sealed: Initializing / Initialized(files, viewMode, isOffline) / Error

lib/presentation/widgets/chat/
├── app_composer_widget.dart                  # UPGRADE: display-only → редактируемый (TextEditingController + FocusNode + onChanged + onSubmitted, maxLines 4–6 растущий); сохранить attach/send/attachment chip
├── app_thread_view_widget.dart               # NEW: общий body ленты (reverse PagedListView: bubbles + date-sep + author-header + system-line + Loading-older) + composer — переиспользуют мобайл-страница и десктоп thread-pane
├── app_thread_header_widget.dart             # NEW: десктоп persistent header (avatar + name(tap→5.4) + folderOpen info-action(→5.4)); реконсилирован под NOX (без members/search/folder)
├── app_date_separator_widget.dart            # NEW: центрированная капсула (Today/Yesterday/d MMM)
├── app_author_header_widget.dart             # NEW: label автора над группой чужих сообщений
└── app_system_line_widget.dart               # NEW: inline системная строка (Chat created by {username})

lib/presentation/widgets/shell/
└── app_side_sheet_widget.dart                # NEW (или helper showRightSideSheet): десктоп правый side-sheet 380 + scrim (5.4 drawer) через showGeneralDialog (slide-in справа)

lib/general/
├── formatters/file_size_formatter.dart       # NEW: static String format(int bytes) → B/KB/MB/GB (intl NumberFormat); используют 5.3 + 5.4
├── mock/identity_mock_data.dart              # NEW: IdentityMockData{currentUserId, currentLabel} — общий мок текущей идентичности (5.2 own/other + согласование с 7.1)
└── text_constants.dart                       # + ≈22 EN-строк (5.2/5.3/5.4); reuse composerHint/tooltipSend/tooltipAttachFile/tooltipRemove/tooltipBack/noConnection/comingSoon/chats* и пр.

lib/presentation/widgets/primitives/file_type.dart  # EDIT: enum FileType вынесен в domain; здесь остаются мапперы noxFileIcon/noxFileColor (import domain enum)
lib/presentation/widgets/chat/app_message_bubble_widget.dart  # EDIT: import MessageStatus из domain (enum продвинут); рендер не меняется

lib/presentation/pages/chats_list_page/chats_list_page.dart   # EDIT: _onTapChat (мобайл) → ChatThreadPage.route(chat) (вместо RoutePlaceholderPage); _threadPane (десктоп) → AppThreadViewWidget реальной ленты (вместо AppDetailEmptyWidget comingSoon)

lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart  # EDIT: активировать строки 5.2/5.3/5.4 (route: тер-офф routeDemo)

# Переиспользуется (без изменений): AppMessageBubbleWidget(статусы)/AppFileChipWidget/AppFileGlyphWidget/AppSegmentedWidget/AppAvatarWidget,
#   AppListDetailWidget/AppDetailEmptyWidget (no-selection), state-виджеты, showAppSnackBar/showAppBanner, PagingStateExt.applyPage,
#   ChatModel/ChatRepository (5.1), DateFormatter (HH:mm + date-sep), BaseBloc/BaseStatePage, ErrorPage (3.1 fatal).

test/
├── domain|data/.../chat/                      # unit: messages-вертикаль (опц.) + chat-files мок
├── general/formatters/file_size_formatter_test.dart   # unit: границы B/KB/MB/GB
├── presentation/pages/{chat_thread,chat_card}_page/   # widget + *_golden_test (light/dark, состояния) + bloc/ bloc_test
├── presentation/pages/file_view_page/         # widget + golden (loading/loaded; мобайл/десктоп) — без bloc_test
└── presentation/widgets/chat/                 # widget+golden: composer(editable), thread-view, thread-header, date-sep, author-header, system-line
```

**Structure Decision**: Один пакет `nox_app`, Clean Architecture слоями-папками. M4 расширяет **domain+data** (messages-вертикаль + chat-files) поверх presentation, по образцу chats-вертикали M3. **Владение BLoC:** 5.2 — `ChatThreadBloc` владеет **`AppThreadViewWidget`** (он переиспользуется мобайл-страницей `ChatThreadPage` и десктоп thread-pane 5.1 — единый владелец, страница лишь хостит виджет); 5.4 — `ChatCardBloc` владеет `ChatCardPage`/`ChatCardBody` (паттерн `ChatsListPage`/`CreateChatPage`: `late final _bloc` в `initState`, `close()` в `dispose`, `BlocProvider.value`). 5.2 — sealed-trio + `PagingState` + optimistic `outgoing` (как `ItemListBloc`), 5.4 — sealed-trio без пагинации. **5.3 — `StatefulWidget` без BLoC** (карв-аут 05 §5.1). Общий `AppThreadViewWidget` рендерит ленту и на мобайл-странице, и в десктоп thread-pane 5.1 (DRY). Каждый экран доступен и через реальную композицию (5.1→5.2→5.3/5.4), и standalone из Галереи (`routeDemo` на образцовых данных). Тесты deep-mirror под `test/`.

## Complexity Tracking

> Заполнено: три пункта требуют осознанной reconciliation (Принцип II/III) — все в этом же change-set; санкционированы owner-решениями (Clarifications) и roadmap.

| Расхождение / усложнение | Зачем нужно | Почему простая альтернатива отклонена |
|---|---|---|
| **Desktop ThreadHeader реконсилируется под NOX** — только аватар + имя + info(→5.4); корпус `01-chats` рисует members/search/folder. | Продуктовая модель NOX: открытое пространство **без участников/подписок**, per-chat-поиск/папки **вне scope** этой итерации (locked `overview.md`/`chat.md`). | Буквальный перенос корпуса (members/search/folder) — отклонён: ввёл бы out-of-scope-сущности. Реконсайл: трактуем как дрейф корпуса (как `02-settings`→Login в M3), `chat.md` не меняется (Принцип II). |
| **Продвижение enum'ов `MessageStatus`/`FileType` в `domain`** — сейчас в presentation (`app_message_bubble_widget.dart` / `primitives/file_type.dart`). | `MessageModel`/`MessageAttachment` (domain) не могут импортировать presentation (Принцип III: `domain` import-free). Единый источник enum'ов нужен и domain-модели, и виджетам. | Дублирующие domain-enum'ы + маппинг — отклонено: два `MessageStatus` запутывают. Продвижение — контейнерная правка (verified: использование ограничено ~6 виджет-файлами + тестами + галереей); мапперы `noxFileIcon`/`noxFileColor` остаются в presentation (импортируют domain-enum). |
| **Апгрейд `AppComposerWidget`** (display-only `value:String` → редактируемый controller-based) + правка её галереи/тестов (Feature-003). | 5.2 требует реальный ввод (растущий `TextField`, `onChanged`/`onSubmitted`); roadmap §6 явно предписывает «апгрейд `AppComposerWidget`». | Новый отдельный editable-композер — отклонён: дублировал бы существующий виджет. Апгрейд in place + обновление единственного использования в `ui_kit_page` и 3 тестов (verified) — минимальная контейнерная правка. |
