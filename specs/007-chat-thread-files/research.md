# Research — Этап M4 (Лента чата и файлы)

Phase 0 плана. Все решения сверены с реальным кодом `lib/` (2026-06-21) и зафиксированными locked-спеками + десктоп/мобайл-корпусами. Открытых `NEEDS CLARIFICATION` нет (три развилки сняты в `/speckit-specify`, три — в `/speckit-clarify`). Формат: Decision / Rationale / Alternatives.

## R1. Слой данных ленты (5.2) — network-only мок-вертикал

- **Decision**: Зеркалить `ItemListBloc`/`ChatsListBloc`. Новые `MessageModel`/`MessageAttachment` (domain) + `GetMessagesConfig{chatId, page}` + мок-`GetMessagesApi` (синтез истории, пагинация старых наверх, `PageMetadata`) + мок-`SendMessageApi` (one-shot POST) + `MessageRepository`/`Impl` (`@LazySingleton(as: MessageRepository, env:[dev,prod,test])`, `BaseRepositoryHelper.execute` → `RepositoryResult`). `ChatThreadBloc` — sealed `Initializing/Initialized/Error`, `PagingState`-в-bloc, `transformer: sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`.
- **Rationale**: Блюпринт 00/05 — network-only carve-out для server-owned пагинированных списков; лента — второй такой список после 5.1. Решено в Clarifications (specify). Повторяет проверенный путь (`GetChatsApi`/`ChatRepositoryImpl`), без реального сервера (данные мок).
- **Alternatives**: In-memory список в bloc — отклонён (нарушает carve-out, дивергенция с M3).

## R2. Обратная пагинация + optimistic send

- **Decision**: `PagedListView<String, MessageModel>(reverse: true)` — новые внизу, старые сверху; авто-подгрузка старых наверх через `fetchNextPage`. Optimistic-сообщения хранятся в `Initialized.outgoing` (отдельный список вне `pagingState`), рендерятся как самые новые (низ ленты). Поток сборки: `[...history(reverse), ...outgoing]`. `messageSent` → немедленно добавляет `MessageModel(status: pending)` в `outgoing` + чистит draft; (заглушенный) `SendMessageApi` → `sent`; debug-исход → `error`; `sendRetried(localId)` повторяет.
- **Rationale**: locked `chat.md` (reverse-`ListView`, infinite scroll вверх, статус `pending→sent`, retry). Разделение history/outgoing избегает гонок пагинации с локально вставленными сообщениями.
- **Alternatives**: Вставлять optimistic прямо в `pagingState.pages` — отклонено (ломает page-of-pages/keys инвариант `PagingStateExt`).

## R3. Идентичность «свои/чужие» — общий мок-источник

- **Decision**: `IdentityMockData{currentUserId, currentLabel}` (`lib/general/mock/`) — единый мок текущей идентичности. `GetMessagesApi` проставляет `authorId` каждому сообщению (часть — `currentUserId`); own = `authorId == IdentityMockData.currentUserId`. Согласуется с мок-идентичностью 7.1 (`SettingsRootBloc`) — при желании 7.1 переводится на тот же источник (не обязателен для M4, но рекомендован).
- **Rationale**: Решено в Clarifications (clarify). Единый источник истины, блюпринт-чисто; backend-фаза заменит на реальную идентичность.
- **Alternatives**: Серверный `isOwn`-флаг (не моделирует идентичность) / хардкод в ленте (дивергенция) — отклонены.

## R4. Источник файлов карточки (5.4)

- **Decision**: `ChatRepository.getChatFiles({required String chatId})` (новый метод существующего репозитория) поверх мок-`GetChatFilesApi`; **без пагинации**. `ChatCardBloc` — sealed `Initializing/Initialized/Error`, `executeLogic(onError:)`.
- **Rationale**: Решено в Clarifications (clarify): «mock-источник + `ChatCardBloc`». Файлы — chat-owned данные → метод на `ChatRepository` (а не новый репозиторий) минимизирует сущности; sealed-trio согласован с network-only-паттерном. Без пагинации — набор вложений невелик и read-only.
- **Alternatives**: Деривация из мок-сообщений (противоречит пагинации ленты, связывает 5.4↔5.2) / inline in-memory (расходится с паттерном) — отклонены.

## R5. Владение состоянием 5.3 — локальный `StatefulWidget`

- **Decision**: `FileViewPage` — `StatefulWidget` без BLoC; download-прогресс — локальное таймер-драйвен состояние (фейк %); `Save`/`Download` — no-op + snackbar.
- **Rationale**: Решено в Clarifications (clarify). Карв-аут блюпринта 05 §5.1 (презентационный экран без репозитория/domain-state — как splash-fade); реального скачивания/кэша/файла нет (Фаза 2). Легче, тестируется widget-тестом.
- **Alternatives**: `FileViewBloc` — отклонён (избыточная церемония для фейкового локального прогресса без репозитория).

## R6. Десктопные раскладки (5.2/5.3/5.4)

- **Decision**: **5.2** — правый thread-pane внутри **существующей** list-detail 5.1 (M3): выбор строки загружает реальную ленту (`AppThreadViewWidget`) с persistent `AppThreadHeaderWidget`, колонка чтения ≤980; заменяет M3-плейсхолдер. **5.3** — центрированный lightbox-`Dialog` (~520) со scrim (`showFileView` адаптивен). **5.4** — правый side-sheet 380 со scrim (`showGeneralDialog` slide-in справа) из info-действия ThreadHeader. Мобайл во всех трёх — fullscreen push.
- **Rationale**: Десктоп-корпус `01-chats` (thread-pane), `08-file` (lightbox 520), `09-drawer` (right drawer 380). Решения по 5.4-drawer и слою данных закрыты в Clarifications. List-detail-механика 5.1 уже построена (M3) — 5.2 встраивается без новой раскладки.
- **Alternatives**: 5.4 detail-pane-swap / центр-Dialog — отклонены в Clarifications (расходятся с корпусом).

## R7. Десктоп ThreadHeader — реконсиляция под NOX

- **Decision**: `AppThreadHeaderWidget` = аватар + имя чата (tap→5.4) + info-действие (`NoxIcons.folderOpen`, tooltip `Chat info` →5.4 side-sheet). **Без** `members` / per-chat `search` / `folder` из корпуса `01-chats`.
- **Rationale**: Продуктовая модель NOX (locked `overview.md`/`chat.md`): открытое пространство без участников/подписок; per-chat-поиск/папки вне scope. Корпусные упоминания — дрейф (трактуем как `02-settings`→Login в M3); `chat.md` не меняется (Принцип II). Reuse `folderOpen` (тот же глиф, что empty-state файлов) — новых SVG не нужно.
- **Alternatives**: Буквальный перенос корпуса — отклонён (out-of-scope-сущности).

## R8. Продвижение enum'ов `MessageStatus`/`FileType` в `domain`

- **Decision**: Вынести чистые enum'ы `MessageStatus {none,pending,sent,error}` и `FileType {image,…,other}` в `lib/domain/model/`. Мапперы `noxFileIcon`/`noxFileColor` остаются в `lib/presentation/widgets/primitives/file_type.dart` (импортируют domain-enum). `AppMessageBubbleWidget` импортирует `MessageStatus` из domain. Рендер не меняется.
- **Rationale**: `domain` import-free (Принцип III); `MessageModel`/`MessageAttachment` нуждаются в этих типах. Единый источник. Использование verified ограничено (`ui_kit_page`, `app_file_chip_widget`, `app_file_glyph_widget`, `file_type.dart`, `app_message_bubble_widget` + их тесты) — контейнерная правка импортов.
- **Alternatives**: Дублирующие domain-enum'ы + маппинг (два `MessageStatus`, путаница) — отклонены.

## R9. Апгрейд `AppComposerWidget` (editable)

- **Decision**: Сделать `AppComposerWidget` редактируемым: `TextEditingController` + `FocusNode` + `onChanged` + `onSubmitted`, растущий `TextField` (`maxLines: 4–6`, далее внутренний скролл), placeholder `composerHint`. Сохранить attach/send/attachment-chip и логику `sendActive`. Обновить единственное использование в `ui_kit_page` + 3 теста (verified).
- **Rationale**: roadmap §6 предписывает апгрейд; 5.2 требует реальный ввод. In-place — без дублирования.
- **Alternatives**: Новый editable-композер рядом с display-only — отклонён (дубликат).

## R10. Форматтер размера файла

- **Decision**: `FileSizeFormatter.format(int bytes)` (static, `lib/general/formatters/file_size_formatter.dart`) → `B`/`KB`/`MB`/`GB` через `intl NumberFormat` (1 дробный знак для KB+). Используют 5.3 (размер) и 5.4 (строки/ячейки); `MessageAttachment.sizeBytes` форматируется при рендере chip.
- **Rationale**: roadmap §6 («размер файла — M4, extend on existing intl»); зеркалит static-стиль `DateFormatter`. Без новой зависимости.
- **Alternatives**: Инстанс-метод на `ValueFormatter` (injectable) — отклонён (для display-хелпера static проще и совместим с `DateFormatter`).

## R11. Зависимости и иконки — без новых

- **Decision**: Новых пакетов нет (`file_picker`/`file_saver`/`path_provider`/`qr_flutter` — Фаза 2). Attach → no-op picker (синтез `MessageAttachment` детерминированного типа/размера). Новых SVG нет: empty 5.2 = `chatBubble`, empty 5.4 = `folderOpen`, info-действие = `folderOpen`, save/download = `download`, статусы = `schedule`/`check`/`error`, attach/send = `attachFile`/`sendFill`.
- **Rationale**: Правило «no new deps» UI-фазы; прецедент M2 (камера) / M3 (QR). Реестр `NoxIcons` verified — все глифы есть.
- **Alternatives**: Реальные плагины сейчас — отклонены в Clarifications.

## R12. Темы стоковых компонентов

- **Decision**: Новых тем, как правило, **не требуется** — лента/composer/header — кастомные виджеты на токенах; `Dialog`/bottom-sheet/`Divider`/`SegmentedButton` уже тематизированы (M1–M3). Для `LinearProgressIndicator` (5.3) — при необходимости добавить `ProgressIndicatorThemeData` в `nox_component_themes.dart` (тематизация, не хардкод); default `ColorScheme` приемлем.
- **Rationale**: Минимизировать поверхность изменений; держать токен-дисциплину.
- **Alternatives**: Хардкод цветов прогресса — запрещён (Принцип IV).

## R13. Снятие M3-плейсхолдеров + Галерея

- **Decision**: В `chats_list_page.dart`: `_onTapChat` (мобайл) → `ChatThreadPage.route(chat)` вместо `RoutePlaceholderPage`; `_threadPane` (десктоп) → реальный `AppThreadViewWidget` вместо `AppDetailEmptyWidget(comingSoon)` (no-selection placeholder `Select a chat` сохраняется). Галерея: строки 5.2/5.3/5.4 — `route:` тер-офф `routeDemo` (перестают быть `Coming soon`).
- **Rationale**: FR-008 (снятие последней заглушки M3). `RoutePlaceholderPage` остаётся для прочих будущих заглушек.
- **Alternatives**: Оставить плейсхолдеры — противоречит цели этапа.
