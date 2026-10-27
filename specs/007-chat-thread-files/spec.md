# Feature Specification: Экраны этапа M4 — Лента чата и файлы

**Feature Branch**: `007-chat-thread-files`

**Created**: 2026-06-21

**Status**: Draft

**Input**: User description: "Запланировать работу из `docs/roadmap.md` — Этап M4 — Лента чата и файлы ⟶ самые сложные, чат-детали"

## Контекст фичи

Фаза 1 проекта (см. `docs/roadmap.md`) — сборка визуального слоя приложения по одному экрану; **интеграция с бэкендом вне scope**. Каркас «Галереи экранов» (M0), семь экранов M1, четыре экрана M2 и три экрана M3 (Tab-bar shell 4.1, Settings root 7.1, Chats list 5.1) уже готовы. Прогресс — **14 / 17 экранов**.

Эта фича закрывает **последний этап фазы 1 — M4** — три **самых сложных** экрана детализации чата:

- **Chat thread / Лента чата (5.2)** — просмотр истории сообщений и отправка текста и файлов; группировка по автору, статусы своих сообщений (`pending`/`sent`/`error`), date-separator'ы, системная строка создания чата, редактируемый composer с attach. Сложность **L**.
- **File view / Просмотр файла (5.3)** — экран информации о файле-вложении: крупная иконка типа + имя + размер, авто-скачивание с прогрессом и сохранение в Downloads. **Превью содержимого нет.** Сложность **M**.
- **Chat card / Карточка чата (5.4)** — read-only карточка: имя чата + список вложений с переключателем List/Grid. Сложность **M**.

**Ключевое отличие M4.** M3 впервые собрал экраны в скелет (шелл хостит реальные 5.1 + 7.1), оставив **единственную** заглушку-назначение — ленту чата 5.2 (мобайл: `RoutePlaceholderPage`; десктоп: плейсхолдер в thread-pane list-detail 5.1). M4 **снимает эту последнюю заглушку** и достраивает весь стек чата: тап по чату в 5.1 (мобайл) и выбор строки (десктоп thread-pane) ведут на **реальную** ленту 5.2; имя/info чата → реальная 5.4; файл-вложение → реальная 5.3. После M4 фаза 1 завершена (17 / 17).

Каждый экран реализуется мультиплатформенно (мобайл + десктоп), со всеми визуальными состояниями на заглушечных данных, в соответствии с зафиксированными locked-спеками `docs/design/spec/screens/` (`chat.md`, `file-view.md`, `chat-card.md`) и десктоп/мобайл-корпусами (`nox-desktop-screens/screens/{01-chats,08-file,09-drawer}.md`, `nox-mobile-screens/screens/{5-2-thread,5-3-file,5-4-card}.md`).

Реальный транспорт/протокол и сервер, реальная отправка/приём сообщений, реальный выбор файла (file picker), реальное скачивание и сохранение в Downloads, l10n и продуктовый навигационный флоу — отдельная (backend) фаза.

## Clarifications

### Session 2026-06-21

- Q: Как показывать «Карточку чата» (5.4) на десктопе? Десктоп-корпус `09-drawer` рисует правый drawer (380) поверх ленты из info-действия ThreadHeader; roadmap (открытый вопрос Q6) помечает это как инференс. → A: **Правый drawer над лентой.** Side-sheet 380 со scrim поверх thread-pane, открываемый из info-действия в десктопном ThreadHeader; точно по корпусу `09-drawer`. Тап на файл → lightbox 5.3.
- Q: Как строить слой данных ленты сообщений (5.2)? Roadmap описывает `ChatThreadBloc` (PagingState-в-bloc, optimistic send), блюпринт требует network-only carve-out; в M3 так сделан список чатов. → A: **Полный network-only вертикал.** Новые `MessageModel` + мок-`GetMessagesApi` (пагинация старых наверх) + мок-`SendMessageApi` (one-shot POST) + `MessageRepository`/`Impl` через DI; `ChatThreadBloc` **sealed** (`Initializing`/`Initialized`/`Error` + `PagingState`-в-bloc, `sequential()`, `executeLogic(onError:)`, optimistic send). Зеркалит `ChatsListBloc`/`ItemListBloc`. Мок-данные, без реального сервера.
- Q: Реальные файловые плагины в M4 или заглушки? Roadmap относит `file_picker`/`file_saver`/`path_provider` к Фазе 2; в M2 камера и в M3 QR — заглушки без новых зависимостей. → A: **Заглушки, без новых зависимостей.** Attach → выбор мок-файла (no-op picker, синтез `FileAttachment`); 5.3 auto-download = фейк-прогресс с %; Save to Downloads = no-op + snackbar. Все точки замены помечены `// TODO(backend):`. Согласуется с прецедентом M2/M3 и правилом «no new deps».
- Q: Как лента (5.2) определяет «свои» сообщения (own vs other) на мок-данных? Спека группирует по идентификатору автора, но не задаёт, откуда берётся «мой» идентификатор. → A: **Общий мок-источник идентичности.** Единый мок «текущей идентичности» (author id), переиспользуемый 5.2 и согласованный с мок-идентичностью 7.1; мок-`GetMessagesApi` проставляет `authorId` каждому сообщению, own = `authorId == currentId`. Единый источник истины (блюпринт).
- Q: Откуда 5.4 берёт список вложений чата? В specify-сессии решили «лёгкий BLoC на мок-источнике», но сам источник не зафиксирован. → A: **Mock-источник + `ChatCardBloc`.** Небольшой mock-источник файлов чата (метод репозитория / отдельный мок-`GetChatFilesApi`) + sealed `ChatCardBloc` (`Initializing`/`Initialized`/`Error`), без пагинации; согласуется с network-only-решением 5.2.
- Q: Как владеть состоянием загрузки на 5.3 (фейк-прогресс скачивания)? Блюпринт 05 §5.1 требует BLoC для async-экранов, но даёт карв-аут для чисто презентационных без репозитория. → A: **Локальный `StatefulWidget`, без BLoC.** Прогресс — локальное таймер-драйвен состояние, без репозитория/BLoC (карв-аут блюпринта 05 §5.1 для чисто презентационных экранов без репозитория); тестируется widget-тестом.

### Унаследованные решения (из M3 / roadmap, действуют в M4)

- **Адаптив — width-driven** по `Constants.railBreakpoint` (840dp), не Platform-driven (Принцип 1 roadmap §3).
- **Десктоп-лента 5.2 — правый thread-pane list-detail 5.1** (корпус `01-chats`): выбор строки в 5.1 загружает реальную ленту справа без push; M4 заменяет M3-плейсхолдер. Мобайл-лента — fullscreen push поверх шелла (нижняя панель скрыта).
- **Десктоп ThreadHeader реконсилируется под продуктовую модель NOX:** только аватар + имя чата + info-действие (→ 5.4 drawer). Упоминания в корпусе `members` / per-chat `search` / `folder` — дрейф (в открытом пространстве нет участников/подписок, per-chat-поиск/папки вне scope этой итерации); трактуются как drift (Принцип II/III), `chat.md` не меняется.
- **Форматтер относительного времени** (`DateFormatter.relative`, лестница `now`/`N min`/`N h`/`Yesterday`/`d MMM`) введён в M3 и переиспользуется в 5.3/5.4; date-separator'ы ленты (`Today`/`Yesterday`/`d MMM`) — по `overview.md / Форматы времени`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Лента чата (Chat thread, 5.2) (Priority: P1)

Пользователь открывает конкретный чат и видит историю сообщений (свои справа, чужие слева, сгруппированные по автору, с date-separator'ами и системной строкой создания чата). Он пишет текст и/или прикрепляет файл и отправляет сообщение; своё сообщение появляется сразу со статусом `pending` → `sent` (или `error` с retry). Скролл вверх авто-подгружает старую историю.

**Why this priority**: Центральный и самый сложный экран фазы 1 и единственная заглушка, оставшаяся после M3. Снятие плейсхолдера ленты завершает стек чата (5.1 → 5.2 → 5.3/5.4) и делает шелл функционально полным. Вводит несущие блоки ленты (редактируемый composer, date-separator, author-header, system-line) и первый network-only вертикал сообщений с optimistic send.

**Independent Test**: Открыть 5.2 из 5.1 (тап по чату на мобайле; выбор строки в thread-pane на десктопе) и standalone из Галереи; на узком окне — `Scaffold` + `AppBar` (back + имя чата) + reverse-`ListView` сообщений + composer снизу; на широком — thread-pane (persistent ThreadHeader + колонка чтения ≤980 + composer) внутри list-detail 5.1; debug-переключателем воспроизвести Initial-loading / Empty / Filled / Loading-older / Sending / Send-error / Offline / Fatal.

**Acceptance Scenarios**:

1. **Given** 5.2 открыт на мобайле в состоянии Filled, **When** он показан, **Then** `Scaffold` (`resizeToAvoidBottomInset: true`) с `AppBar` (back-стрелка + центральный title = **только имя чата**, тап → 5.4), обратный (`reverse: true`) `ListView` сообщений (новые внизу) и composer снизу; нижняя панель шелла не видна (5.2 — push поверх 4.1).
2. **Given** в ленте есть свои и чужие сообщения, **When** они отрисованы, **Then** свои — справа, фон `primaryContainer`/`onPrimaryContainer`; чужие — слева, фон `surfaceContainerHigh`/`onSurface`; принадлежность и группировка — по **идентификатору** автора; подряд идущие сообщения одного автора объединены в группу с одним author-header (текущий label, для чужих); на каждом сообщении — время `HH:mm` в углу bubble; между днями — date-separator (`Today`/`Yesterday`/`d MMM`).
3. **Given** свои сообщения, **When** показан их статус, **Then** в углу bubble: `pending` → часики (`onSurfaceVariant`), `sent` → одна галочка (`onSurfaceVariant`), `error` → `error_outline` (`ColorScheme.error`); **delivered/read не используются**. В начале истории — inline системная строка `Chat created by {username}` (сообщением не считается).
4. **Given** пользователь вводит текст и/или прикрепляет файл, **When** composer активен, **Then** многострочное растущее поле (`maxLines` 4–6, далее внутренний скролл), слева attach (paperclip), справа send (paper-plane); send **активна**, если поле непустое **или** есть вложение, иначе disabled; прикреплённый файл показан как removable file-chip (иконка типа + имя + размер + `×`) над строкой ввода.
5. **Given** пользователь нажимает send, **When** отправка идёт, **Then** сообщение появляется в ленте сразу со статусом `pending`, поле/вложение очищаются (optimistic send); по (заглушенному) успеху статус → `sent`; при ошибке (debug) → `error`, тап по сообщению/статусу → retry.
6. **Given** пользователь скроллит к началу истории, **When** достигнут порог, **Then** старые сообщения авто-подгружаются (infinite scroll вверх), сверху списка — `CircularProgressIndicator` (Loading-older); без явного жеста.
7. **Given** в чате нет сообщений, **When** Empty, **Then** системная строка `Chat created by …` показана всегда, а ниже неё — empty-state (иллюстрация + `No messages yet` / `Send the first one.`).
8. **Given** нет соединения (debug), **When** Offline, **Then** постоянный `MaterialBanner` `No connection` сверху; отправка офлайн → `pending` до восстановления. Fatal → 3.1 (embedded).
9. **Given** широкое окно (десктоп), **When** в 5.1 выбрана строка чата, **Then** реальная лента 5.2 загружается в правый thread-pane (replaces M3-плейсхолдер) **без push**: persistent ThreadHeader (аватар + имя + info → 5.4 drawer), поток сообщений в колонке чтения ≤980, composer снизу; transient-фидбек — `SnackBar` по центру над thread-pane; те же состояния, что на мобайле.

---

### User Story 2 — Просмотр файла (File view, 5.3) (Priority: P2)

Пользователь тапает файл-вложение (в сообщении 5.2 или в карточке 5.4) и попадает на экран файла: крупная иконка типа, имя, размер. Если файл не в кэше — идёт авто-скачивание с прогресс-баром; по готовности доступно сохранение в Downloads. Превью содержимого нет.

**Why this priority**: Общая цель тапа по файлу из 5.2 и 5.4; вводит форматтер размера файла и фейк-прогресс загрузки. P2, потому что зависит от 5.2 (источник вложений) и проще ленты, но нужен для замыкания файлового потока.

**Independent Test**: Открыть 5.3 из 5.2 (тап на file-chip) и из 5.4 (тап на файл) и standalone из Галереи; на узком окне — fullscreen `Scaffold` (AppBar back + имя файла + `Save`) с центрированной column (иконка типа + имя + размер); на широком — центрированный lightbox-`Dialog` 520 (header + крупный глиф + имя + размер + `Download`); debug-переключателем воспроизвести Loading (определённый %) / Loaded / Inline-error / Fatal.

**Acceptance Scenarios**:

1. **Given** 5.3 открыт на мобайле, **When** он показан, **Then** `Scaffold` с `AppBar` (`ColorScheme.surface`): back-стрелка, title = имя файла (ellipsis), справа — `Save`; body — центрированная column: крупная иконка типа (по единому маппингу `overview.md / Файлы`) + filename (по центру, перенос) + размер (например `2.4 MB`).
2. **Given** файл не в кэше, **When** экран открыт, **Then** Loading: горизонтальный `LinearProgressIndicator` с определённым % (фейк-прогресс), `Save` disabled; по достижении 100% → Loaded: progress скрыт, `Save` enabled. Если файл уже в кэше — сразу Loaded.
3. **Given** Loaded, **When** пользователь тапает `Save`, **Then** (заглушенное) копирование в Downloads + `SnackBar` `Saved to Downloads`.
4. **Given** сбой сети (debug), **When** Inline-error, **Then** transient `SnackBar` с action retry (`Could not download file. Check your connection and try again.`); Fatal (файл удалён сервером / общая сетевая fatal) → 3.1 (embedded).
5. **Given** широкое окно (десктоп), **When** 5.3 открыт, **Then** центрированный lightbox-`Dialog` (520) с усиленным scrim (корпус `08-file`): header (иконка типа + имя + download + close), крупный глиф типа, имя, размер, `Download`; Downloading → `Downloading… N%`; close/scrim → возврат к ленте.
6. **Given** long-press / share / open-in-external, **When** пользователь пытается, **Then** no-op (вне scope этой итерации).

---

### User Story 3 — Карточка чата (Chat card, 5.4) (Priority: P3)

Пользователь тапает имя чата (мобайл AppBar 5.2) или info-действие (десктоп ThreadHeader) и видит read-only карточку чата: имя чата и список всех вложений с переключателем List / Grid. Метаданных (создатель, дата, счётчики) нет; имя не редактируется.

**Why this priority**: Завершает стек чата и Галерею (17/17). P3, потому что зависит от 5.2 (точка входа) и 5.3 (цель тапа по файлу) и наименее критичен для основного флоу обмена сообщениями.

**Independent Test**: Открыть 5.4 из 5.2 (тап на имя/info) и standalone из Галереи; на узком окне — fullscreen `Scaffold` (AppBar back + имя чата) с header (аватар 56 + имя) и секцией `Files` (List/Grid `SegmentedButton` + строки/сетка); на широком — правый drawer (380) со scrim поверх ленты; debug-переключателем воспроизвести Initial-loading / Loaded (List) / Loaded (Grid) / Empty (files) / Offline / Fatal.

**Acceptance Scenarios**:

1. **Given** 5.4 открыт на мобайле, **When** он показан, **Then** `Scaffold` с `AppBar` (back + title = имя чата) и прокручиваемая column: header (аватар 56 + имя чата крупно) + секция `Files` (заголовок `Files` + `SegmentedButton` List/Grid).
2. **Given** секция Files в режиме List, **When** показана, **Then** `ListTile`-строки: иконка типа (по маппингу) + имя файла (ellipsis) + размер; тап по строке → 5.3.
3. **Given** секция Files в режиме Grid, **When** переключён `SegmentedButton`, **Then** ~3 колонки квадратных тайлов (gap `space/2`): иконка типа + имя (truncate) + размер; превью содержимого нет; тап по ячейке → 5.3.
4. **Given** вложений нет, **When** Empty (files), **Then** в области секции — empty-state (иллюстрация + `No files yet` / `Files sent in this chat will appear here.`); header остаётся виден.
5. **Given** сбой загрузки / офлайн (debug), **When** Offline/Inline-error, **Then** постоянный `MaterialBanner` сверху (`Could not load chat info. Check your connection and try again.`); Fatal → 3.1 (embedded).
6. **Given** широкое окно (десктоп), **When** info-действие ThreadHeader, **Then** правый drawer (380) со scrim поверх thread-pane (корпус `09-drawer`): заголовок `Details`, аватар + имя, секция `Files` (List/Grid, Grid — 2 колонки), close/scrim → закрытие; тап по файлу → lightbox 5.3.
7. **Given** edit name / description / mute / pin / report, **When** пользователь ищет действие, **Then** их нет (read-only; имя фиксируется при создании в 6.1); long-press — no-op.

---

### Edge Cases

- **Лента (5.2) — группировка:** смена label автора не ломает группировку (ключ — идентификатор, label re-fetched на момент рендера); подряд идущие сообщения одного идентификатора → одна группа с одним header; чередование авторов → новый header.
- **Лента (5.2) — optimistic send:** при ошибке отправки сообщение остаётся в ленте со статусом `error` (не исчезает); retry повторяет отправку того же сообщения; офлайн → `pending` до восстановления; быстрые повторные send не дублируют и не теряют сообщения.
- **Лента (5.2) — пустая vs системная строка:** системная строка `Chat created by …` показывается всегда и **не считается** сообщением — Empty-state рисуется отдельно ниже неё.
- **Лента (5.2) — composer:** при росте поля до лимита включается внутренний скролл, лента не перекрывается клавиатурой (`resizeToAvoidBottomInset`); удаление вложенного chip (`×`) при пустом тексте → send снова disabled.
- **Лента (5.2) — десктоп:** thread-pane без собственного back (выбор/закрытие — view-state list-detail 5.1); смена выбранного чата меняет ленту без push; no-selection → placeholder `Select a chat` (из M3).
- **Файл (5.3):** если файл уже в кэше — сразу Loaded (без повторного скачивания); очень длинное имя — ellipsis в AppBar и перенос в body; неизвестный тип → иконка `other` (`insert_drive_file` маппинг); размер форматируется в B/KB/MB/GB.
- **Карточка (5.4):** Empty-state в секции Files при сохранённом header; не-латиница/символы в имени чата → generated-аватар имеет fallback-иконку; переключение List/Grid сохраняет позицию/состояние секции.
- **Все экраны:** компоновка устойчива к большому масштабу текста и к узкому/широкому окну; debug-контролы воспроизведения состояний доступны только в dev-превью и не входят в продуктовый UI.

## Requirements *(mandatory)*

### Functional Requirements — сквозные

- **FR-001**: Все три экрана M4 (Chat thread 5.2, File view 5.3, Chat card 5.4) MUST быть реализованы; соответствующие строки «Галереи экранов» MUST активироваться (перестают быть `Coming soon`). После M4 прогресс фазы 1 — 17 / 17 экранов.
- **FR-002**: Каждый экран MUST иметь две адаптивные раскладки — мобайл (узкое окно) и десктоп (широкое окно), выбираемые по ширине окна (`LayoutBuilder` по `Constants.railBreakpoint` = 840dp), а не по платформе. Ключевые десктоп-отличия: 5.2 — правый thread-pane list-detail 5.1 (persistent ThreadHeader, колонка ≤980) вместо fullscreen push; 5.3 — центрированный lightbox-`Dialog` 520 вместо fullscreen push; 5.4 — правый drawer 380 со scrim поверх ленты вместо fullscreen push.
- **FR-003**: Каждый экран MUST корректно отображаться в светлой и тёмной теме и при переключении. M4 **не вводит** новых brand-fixed исключений (их по-прежнему два: тёмный splash 1.1, светлая QR-поверхность 7.1); всё в M4 темизируется. Декоративные brand-цвета иконок типов файлов (`noxFileColor`) — допустимое исключение из `ColorScheme` (уже введено в UI-kit).
- **FR-004**: Вся пользовательская микрокопия MUST быть на английском через `TextConstants`; строковых литералов в виджетах и русского текста в UI быть не должно. Новые строки M4 (`Message`, `Attach`, `Send`, `Remove`, `Tap to retry`, `No messages yet`, `Send the first one.`, `Chat created by {username}`, `Save`, `Saved to Downloads`, `Could not download file. …`, `Download`, `Downloading… {n}%`, `Files`, `List`, `Grid`, `No files yet`, `Files sent in this chat will appear here.`, `Details`, `Could not load chat info. …`) добавляются в `TextConstants`.
- **FR-005**: Все визуальные состояния каждого экрана, определённые его спекой, MUST быть воспроизводимы на заглушечных данных без бэкенда — через сочетание in-memory мок-набора (сообщения, вложения) и локальных debug-переключателей (loading/loading-older/sending/send-error/offline/fatal/empty, исход скачивания/сохранения).
- **FR-006**: Любая бэкенд-зависимость (загрузка/пагинация сообщений, отправка сообщения, выбор файла, скачивание/кэш файла, сохранение в Downloads, реальная маршрутизация) MUST быть заглушена (фейковый результат/no-op) и помечена точкой будущей замены `// TODO(backend):`.
- **FR-007**: Каждый экран MUST быть покрыт автотестами уровня widget и golden (светлая + тёмная темы), по правилам именования/тегов проекта, через харнес `pumpApp`. Форматтер размера файла и новые виджеты ленты — покрываются unit/widget-тестами; `ChatThreadBloc` — `bloc_test` против test-env DI.
- **FR-008**: M4 MUST **снять последнюю заглушку-назначение M3** — ленту чата 5.2: тап по чату в 5.1 (мобайл) MUST вести на реальную 5.2 (заменяя `RoutePlaceholderPage`); выбор строки в thread-pane 5.1 (десктоп) MUST загружать реальную ленту (заменяя `AppDetailEmptyWidget`-плейсхолдер); имя/info чата → реальная 5.4; файл-вложение (5.2/5.4) → реальная 5.3. Стек чата (5.1 → 5.2 → 5.3/5.4) после M4 полностью связан реальной навигацией.
- **FR-009**: Этап MUST ввести и переиспользовать несущие блоки ленты без дивергенции: (а) **редактируемый composer** (апгрейд `AppComposerWidget` от display-only к controller-based: растущий `TextField` `maxLines` 4–6, attach, send-enable, removable attachment chip); (б) **`AppDateSeparatorWidget`**, **`AppAuthorHeaderWidget`**, **`AppSystemLineWidget`**; (в) десктопный **ThreadHeader** (аватар + имя + info) и **chat-info drawer** (5.4 desktop); (г) **форматтер размера файла** (B/KB/MB/GB на существующем `intl`, без новой зависимости). Несколько несогласованных реализаций не допускаются.
- **FR-010**: Галерея экранов MUST давать доступ к каждому экрану standalone (паттерн `routeDemo`): 5.2 — на образцовом чате (мобайл push / десктоп thread-pane-превью с back-аффордансом); 5.3 — на образцовом файле (мобайл push / десктоп `Dialog`); 5.4 — на образцовом чате (мобайл push / десктоп drawer-превью). Реальная композиция (5.1 → 5.2 → 5.3/5.4) проверяется из строки 5.1.
- **FR-011**: M4 MUST соблюдать токен-дисциплину (никаких сырых `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle` в коде экранов; цвет — `ColorScheme`/`context.appColors`/`NoxBrand`-глифы файлов; отступы — `AppSpacingTokens`/`NoxSpacing`/`NoxRadius`; типографика — `textTheme`/`AppTextStyleTokens`) и использовать только SVG-иконки через `NoxIcons` + `AppIconWidget` (никаких `Icons.*` — спека/handoff про иконки устарели, верить коду; статусы сообщений маппятся на `NoxIcons.schedule`/`check`/`error`, как в существующем `AppMessageBubbleWidget`).

### Functional Requirements — Chat thread (5.2)

- **FR-020**: 5.2 MUST на мобайле выводить `Scaffold` (`resizeToAvoidBottomInset: true`) с `AppBar` (back-стрелка + центральный title = имя чата, тап → 5.4), обратным (`reverse: true`) `ListView` сообщений (новые внизу, старые сверху) и composer снизу; нижняя панель шелла на 5.2 не видна (push поверх 4.1).
- **FR-021**: Сообщения MUST рендериться через `AppMessageBubbleWidget` (M3 rounded, без хвоста): свои справа (`primaryContainer`/`onPrimaryContainer`), чужие слева (`surfaceContainerHigh`/`onSurface`); принадлежность («свои/чужие») и группировка — по **идентификатору** автора (стабильный ключ), не по label; max-ширина bubble ~80%. Принадлежность определяется сравнением `authorId` сообщения с **общим мок-источником текущей идентичности** `IdentityMockData` (own = `authorId == currentId`). Значения согласованы со значениями мок-идентичности 7.1; единый рантайм-источник идентичности для 7.1 — Фаза 2 (M4 7.1 не трогает).
- **FR-022**: Подряд идущие сообщения одного автора (по идентификатору) MUST объединяться в группу с **одним** author-header (`AppAuthorHeaderWidget`, текущий label автора, для чужих групп; per-author аватаров в ленте нет). На каждом сообщении — время `HH:mm` в углу bubble.
- **FR-023**: Между сообщениями разных календарных дней MUST показываться date-separator (`AppDateSeparatorWidget`, лестница `Today`/`Yesterday`/`d MMM` из `overview.md`). В начале истории — inline системная строка `AppSystemLineWidget` `Chat created by {username}` (не считается сообщением; других системных событий нет).
- **FR-024**: Статус **только своих** сообщений MUST показываться в углу bubble: `pending` → `schedule` (часики, `onSurfaceVariant`); `sent` → `check` (одна галочка, `onSurfaceVariant`); `error` → `error_outline` (`ColorScheme.error`). **delivered/read не используются** (открытое пространство, нет фиксированного получателя).
- **FR-025**: Composer MUST быть редактируемым: многострочное растущее поле (`TextField`, `maxLines` 4–6, далее внутренний скролл, placeholder `Message`), attach-иконка (paperclip) слева, send-иконка (paper-plane) справа. Send **активна**, если поле непустое **или** есть вложение, иначе disabled. Прикреплённый, но не отправленный файл — removable file-chip (иконка типа + имя + размер + `×`) над строкой ввода (reuse `AppFileChipWidget(removable: true)`).
- **FR-026**: Тап на attach MUST открывать **заглушенный** file picker (любой тип; реальный `file_picker` — Фаза 2, `// TODO(backend):`): выбранный мок-файл синтезируется как `FileAttachment` и показывается chip в composer; можно прикрепить файл и/или ввести текст в одном сообщении.
- **FR-027**: Тап на send MUST выполнять **optimistic send**: сообщение немедленно добавляется в ленту со статусом `pending`, поле/вложение очищаются; по (заглушенному) успеху статус → `sent`; при ошибке (debug-сценарий) → `error`. Тап по сообщению в Send-error (или по его статус-иконке) → retry той же отправки.
- **FR-028**: Скролл к началу истории MUST авто-подгружать старые сообщения (infinite scroll вверх до порога, без явного жеста); во время подгрузки — `CircularProgressIndicator` сверху списка (Loading-older). Long-press на сообщении — no-op (reactions/edit/delete вне scope).
- **FR-029**: 5.2 MUST воспроизводить состояния Initial-loading (centered `CircularProgressIndicator`) / Empty (системная строка + empty-state `No messages yet` / `Send the first one.`) / Filled / Loading-older / Sending (`pending`→`sent`) / Send-error (`error` + retry) / Offline (постоянный `MaterialBanner` `No connection` сверху, отправка → `pending`) / Fatal → 3.1 (embedded); воспроизводимы мок-набором + debug-переключателем.
- **FR-030**: На десктопе 5.2 MUST рендериться как правый **thread-pane** list-detail 5.1 (корпус `01-chats`): persistent **ThreadHeader** (аватар + имя чата + info-действие → 5.4 drawer), поток сообщений в колонке чтения ≤980, composer снизу; выбор строки в 5.1 загружает ленту **без push** (заменяет M3-плейсхолдер); transient-фидбек — `SnackBar` по центру над thread-pane; offline-баннер — в обеих панелях. ThreadHeader реконсилируется под NOX-модель (без `members`/per-chat `search`/`folder` — дрейф корпуса).
- **FR-031**: 5.2 MUST ввести **`ChatThreadBloc`** поверх **network-only мок-вертикала сообщений** (carve-out блюпринта, второй после списка чатов; зеркалит `ChatsListBloc`/`ItemListBloc`): новые `MessageModel` (domain) + мок-`GetMessagesApi` (синтез детерминированной истории, пагинация старых наверх; проставляет `authorId` из **общего мок-источника текущей идентичности** — own/other, согласовано с 7.1) + мок-`SendMessageApi` (one-shot POST) + `MessageRepository`/`Impl` через DI, возвращающий `RepositoryResult`, с `PagingState`-в-bloc. BLoC — **sealed** `Initializing`/`Initialized`/`Error`, загрузка через `executeLogic(onError:)` + `sequential()`, держит список сообщений, статусы своих сообщений, optimistic-очередь отправки, loading-older/offline/error. **Мок-данные, без реального сервера**; реальный транспорт/кэш заглушён `// TODO(backend):`.

### Functional Requirements — File view (5.3)

- **FR-040**: 5.3 MUST на мобайле выводить `Scaffold` с `AppBar` (`ColorScheme.surface`): back-стрелка, title = имя файла (ellipsis при переполнении), справа — `Save`; body — центрированная column: крупная иконка типа (по единому маппингу `overview.md / Файлы`, reuse `AppFileGlyphWidget`) + filename (по центру, перенос если длинный) + размер (например `2.4 MB`). **Превью содержимого не показывается.**
- **FR-041**: При открытии 5.3 MUST: если файл не в кэше — запускать **заглушенное** auto-скачивание с определённым % (горизонтальный `LinearProgressIndicator`, `Save` disabled), по 100% → Loaded (progress скрыт, `Save` enabled); если файл уже в кэше — сразу Loaded. Реальное скачивание/кэш — `// TODO(backend):`.
- **FR-042**: Тап на `Save` (Loaded) MUST выполнять **заглушенное** копирование в Downloads (no-op, без `file_saver`/`path_provider`) + `SnackBar` `Saved to Downloads`. Реальное сохранение — Фаза 2, `// TODO(backend):`.
- **FR-043**: 5.3 MUST воспроизводить состояния Loading (`LinearProgressIndicator` с %, `Save` disabled) / Loaded (`Save` enabled) / Inline-error (transient `SnackBar` с retry, `Could not download file. Check your connection and try again.`) / Fatal (файл удалён сервером / общая сетевая fatal → 3.1 embedded); воспроизводимы debug-переключателем. Long-press / share / open-in-external — no-op (вне scope).
- **FR-044**: На десктопе 5.3 MUST рендериться как центрированный **lightbox-`Dialog`** (~520) с усиленным scrim (корпус `08-file`): header (иконка типа + имя + download + close), крупный глиф типа, имя, размер, кнопка `Download`; Downloading → определённый progress + `Downloading… {n}%`; close/scrim → возврат к ленте.
- **FR-045**: 5.3 MUST ввести **форматтер размера файла** (байты → `2.4 MB` / `512 KB` / `1.2 GB` и т.п.) на существующем `intl` (без новой зависимости); форматтер используется 5.3 и 5.4 (и любым file-chip, требующим форматирования из байт).

### Functional Requirements — Chat card (5.4)

- **FR-060**: 5.4 MUST на мобайле выводить `Scaffold` с `AppBar` (back + title = имя чата) и прокручиваемую column: **header** (аватар 56 через `AppAvatarWidget` + имя чата крупно) + секция **`Files`** (заголовок `Files` + `SegmentedButton` List/Grid через `AppSegmentedWidget`). Экран **read-only**: имя не редактируется; mute/pin/report/edit — нет; метаданных (создатель/дата/счётчики) нет.
- **FR-061**: Секция Files MUST поддерживать два режима: **List** (`ListTile`-строки: иконка типа + имя (ellipsis) + размер) и **Grid** (~3 колонки квадратных тайлов, gap `space/2`: иконка типа + имя (truncate) + размер); превью содержимого нет; тап по строке/ячейке → 5.3.
- **FR-062**: 5.4 MUST воспроизводить состояния Initial-loading (centered `CircularProgressIndicator`) / Loaded (List) / Loaded (Grid) / Empty-files (empty-state `No files yet` / `Files sent in this chat will appear here.` в области секции, header виден) / Offline-Inline-error (постоянный `MaterialBanner` `Could not load chat info. …` сверху) / Fatal → 3.1 (embedded); воспроизводимы мок-набором + debug-переключателем. Long-press — no-op.
- **FR-063**: На десктопе 5.4 MUST рендериться как правый **chat-info drawer** (~380) со scrim поверх thread-pane (корпус `09-drawer`), открываемый из info-действия ThreadHeader (5.2 desktop): заголовок `Details`, аватар + имя чата, секция `Files` (List/Grid, Grid — 2 колонки), close/scrim → закрытие; тап по файлу → lightbox 5.3.
- **FR-064**: 5.4 MUST переиспользовать готовые виджеты (`AppAvatarWidget`, `AppSegmentedWidget`, `AppFileGlyphWidget`/`AppFileChipWidget`, state-виджеты `AppEmptyContentWidget`/`AppProgressWidget`/`AppErrorWidget`, форматтер размера файла из FR-045) и загружать вложения чата через sealed **`ChatCardBloc`** (`Initializing`/`Initialized`/`Error`) поверх небольшого mock-источника файлов чата (метод репозитория / отдельный мок-`GetChatFilesApi`, **без пагинации**); реальная загрузка — `// TODO(backend):`.

### Key Entities

- **Current identity (мок)**: общий мок «текущей идентичности» (author id), переиспользуемый 5.2 для определения «своих» сообщений (own = `authorId == currentId`) и согласованный с мок-идентичностью 7.1 (Settings). Значение — заглушка, не хранится.
- **Message (мок)**: сообщение ленты — id, chatId, authorId (стабильный ключ: определяет свои/чужие и группировку — сравнением с Current identity), authorLabel (текущий display-name, re-fetched на момент рендера), text (опц.), attachment (опц. `FileAttachment`), sentAt (`DateTime`, → `HH:mm` + date-separator), status (только для своих: `pending`/`sent`/`error`; для чужих — none), isSystem (системная строка «Chat created by …»). Значения — заглушка, не хранятся.
- **FileAttachment (мок)**: вложение — id, тип (`FileType`: image/video/audio/pdf/doc/sheet/text/archive/other), имя, размер в байтах (форматируется FR-045), cached (для 5.3). Превью содержимого нет.
- **ChatThread view-state (десктоп)**: выбранный чат (из list-detail 5.1) → загруженная лента в thread-pane; состояние ThreadHeader (имя, info-действие) и open/closed chat-info drawer (5.4).
- **Send outcome (мок)**: optimistic-результат отправки — немедленный `pending` → (заглушенный) `sent` или `error` (debug) с retry.
- **Download outcome (мок)**: состояние скачивания файла (5.3) — Loading (определённый %) → Loaded (cached) или Inline-error (retry); Save → no-op + `Saved to Downloads`.
- **Files collection (мок, 5.4)**: список вложений чата для секции Files (List/Grid), загружается через sealed `ChatCardBloc` из небольшого mock-источника файлов чата (метод репозитория / мок-`GetChatFilesApi`, без пагинации); пуст → empty-state.
- **Screen entry (Галерея)**: записи `5.2`/`5.3`/`5.4` (раздел `Chats`) — активируются (route выставляется), standalone `routeDemo` для изолированной проверки в обеих темах/раскладках.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Все 3 экрана M4 доступны из Галереи (standalone) и через реальную композицию (5.1 → 5.2 → 5.3/5.4) и отображаются без ошибок рендеринга в обеих темах и в обеих раскладках (узкое и широкое окно). Прогресс фазы 1 — 17 / 17 экранов.
- **SC-002**: Для каждого экрана 100% состояний, определённых его спекой, демонстрируемы на заглушечных данных (мок-набор + debug-переключатель): 5.2 — Initial-loading/Empty/Filled/Loading-older/Sending/Send-error/Offline/Fatal; 5.3 — Loading/Loaded/Inline-error/Fatal; 5.4 — Initial-loading/Loaded-List/Loaded-Grid/Empty/Offline/Fatal.
- **SC-003**: Последняя заглушка M3 снята: тап по чату в 5.1 (мобайл) и выбор строки (десктоп thread-pane) ведут на **реальную** ленту 5.2; имя/info → реальная 5.4; файл-вложение → реальная 5.3. Плейсхолдеров ленты (`RoutePlaceholderPage` мобайл / `AppDetailEmptyWidget` thread-content десктоп) в стеке чата не остаётся.
- **SC-004**: Адаптив работает по ширине окна (840dp): 5.2 — fullscreen push ↔ thread-pane (≤980); 5.3 — fullscreen push ↔ lightbox-`Dialog` 520; 5.4 — fullscreen push ↔ drawer 380; без `Platform`-проверок для лейаута.
- **SC-005**: Несущие блоки ленты введены один раз и переиспользуются без дублирующих несогласованных реализаций: редактируемый `AppComposerWidget`, `AppDateSeparatorWidget`, `AppAuthorHeaderWidget`, `AppSystemLineWidget`, десктопный ThreadHeader + chat-info drawer, форматтер размера файла.
- **SC-006**: Optimistic send работает: своё сообщение появляется со статусом `pending` и переходит в `sent` (успех) или `error` (debug) с работающим retry; группировка по идентификатору и date-separator'ы корректны на граничных данных (смена label, границы дней).
- **SC-007**: `ChatThreadBloc` построен как network-only вертикал по паттерну M3 (sealed-состояния, `PagingState`-в-bloc, `sequential()`, `executeLogic(onError:)`), на мок-репозитории через DI; реальный транспорт заглушён и помечен `// TODO(backend):`. Никаких новых зависимостей (`file_picker`/`file_saver`/`path_provider`/`qr_flutter` и т.п.) не добавлено.
- **SC-008**: 100% пользовательской микрокопии — английская; 0 строк русского текста в UI; каждый экран покрыт widget- и golden-тестами (светлая + тёмная), `ChatThreadBloc` — `bloc_test`, форматтер размера — unit-тестом; проектный гейт качества (`make gate`) проходит зелёным.

## Assumptions

- Бэкенд, транспорт и протокол не выбраны (Конституция, тех-контекст) — поэтому все серверные зависимости (загрузка/пагинация/отправка сообщений, выбор/скачивание/сохранение файла, реальная маршрутизация) заглушены и помечены точками будущей замены `// TODO(backend):`.
- **M4 снимает последнюю заглушку-назначение M3** (лента 5.2) и достраивает весь стек чата реальной навигацией (5.1 → 5.2 → 5.3/5.4); это завершает фазу 1 (17/17) — решено в Clarifications / FR-008.
- **Лента 5.2 = полный network-only мок-вертикал** (`MessageModel` + мок-`GetMessagesApi`/`SendMessageApi` + `MessageRepository`/`Impl` + `ChatThreadBloc` с `PagingState`-в-bloc + optimistic send), зеркалит `ChatsListBloc`/`ItemListBloc` (решено в Clarifications; блюпринт network-only carve-out, roadmap).
- **Файловые действия заглушены без новых зависимостей** (attach = no-op picker + синтез `FileAttachment`; 5.3 download = фейк-прогресс; Save = no-op + snackbar); `file_picker`/`file_saver`/`path_provider` — Фаза 2 (решено в Clarifications; правило «no new deps», прецедент M2 камера / M3 QR).
- **Десктоп 5.4 = правый drawer 380 поверх ленты** из info-действия ThreadHeader (корпус `09-drawer`; решено в Clarifications, закрывает roadmap Q6); десктоп 5.2 = thread-pane list-detail 5.1 (корпус `01-chats`); десктоп 5.3 = lightbox-`Dialog` 520 (корпус `08-file`).
- **Десктопный ThreadHeader реконсилируется под NOX-модель** — аватар + имя + info (→ 5.4); `members`/per-chat `search`/`folder` из корпуса трактуются как дрейф (открытое пространство без участников/подписок; per-chat-поиск/папки вне scope), `chat.md` не меняется (Принцип II/III).
- **Форматтер размера файла** вводится в 5.3 на существующем `intl` (B/KB/MB/GB); переиспользуется 5.4. Форматтер относительного времени (`DateFormatter.relative`) и date-маппинг введены ранее.
- **Редактируемый composer** — апгрейд существующего display-only `AppComposerWidget` (controller-based, растущий `TextField`); статус-иконки и bubble-стиль уже есть в `AppMessageBubbleWidget`/`AppFileChipWidget` (Feature-003) и используются как есть.
- Экраны 5.2/5.4 — навигабельные страницы с реальной async-логикой → 5.2 владеет `ChatThreadBloc` (default 05 §5.1); **5.4 владеет sealed `ChatCardBloc`** поверх небольшого mock-источника файлов чата (метод репозитория / мок-`GetChatFilesApi`, без пагинации); **5.3 — локальный `StatefulWidget`** (таймер-драйвен фейк-прогресс скачивания, без репозитория/BLoC — карв-аут блюпринта 05 §5.1 для чисто презентационных экранов без репозитория), тестируется widget-тестом. Переиспользуемые виджеты BLoC не имеют.
- **Принадлежность сообщений (5.2)** определяется **общим мок-источником текущей идентичности** (author id), согласованным с мок-идентичностью 7.1; own = `authorId == currentId` (решено в Clarifications). Реальное чтение идентичности — Фаза 2.
- Каждый экран доступен и через реальную композицию, и standalone из Галереи (`routeDemo` с preview-аффордансами), зеркаля паттерн M2/M3; debug-переключатели состояний — только в dev-превью.
- Десктоп-корпус присутствует для всех трёх экранов (`01-chats`, `08-file`, `09-drawer`) и используется как авторитетный desktop-референс наряду с locked-спеками.

## Out of Scope

- Реальный транспорт/протокол/сервер; реальная отправка/приём/пагинация сообщений; реальный выбор файла (file picker), скачивание, кэш и сохранение в Downloads.
- Reactions / stickers / voice messages / edit / delete / long-press-меню сообщений; mentions / threads; per-message аватары; delivered/read-статусы.
- Per-chat search / folders / members; mute / pin / report; редактирование имени или описания чата (read-only, фиксируется в 6.1); метаданные чата (создатель/дата/счётчики) на 5.4.
- Превью содержимого файлов (везде — только иконка типа); share / open-in-external на 5.3.
- Продуктовый навигационный флоу за пределами стека чата и замена Галереи реальной навигацией; l10n (EN+UK) и персистентность; реальное определение офлайна/соединения (в M4 — debug-переключатель).
- Новые зависимости (`file_picker`, `file_saver`, `path_provider`, `qr_flutter` и пр.) — Фаза 2.
- Любая backend-интеграция.
