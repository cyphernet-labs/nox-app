# Quickstart — Проверка этапа M4 (Лента чата и файлы)

Гайд запуска и валидации трёх экранов M4 (5.2 Chat thread, 5.3 File view, 5.4 Chat card) и снятия последней заглушки M3. Детали API — в [contracts/](./contracts/), модель — в [data-model.md](./data-model.md). Бэкенда нет — всё на мок-данных + debug-переключателях.

## Предусловия

- FVM-pinned Flutter `3.44.1`; `make deps` выполнен.
- Codegen прошёл: `make generate` (freezed для `MessageModel`/`MessageAttachment`/`GetMessagesConfig` + BLoC-состояния + DI-регистрация мок-репозиториев).

## Запуск

```bash
fvm flutter run --dart-define-from-file=config/stage.json            # мобайл-таргет (узкое окно)
fvm flutter run --dart-define-from-file=config/stage.json -d macos   # десктоп (широкое окно → list-detail/overlay)
```

Точка входа — `HomePage` → **Open Screens** → `ScreensGalleryPage`. Раздел **Chats**: строки **5.2 / 5.3 / 5.4** активны (не `Coming soon`). Тема — `AppThemeToggle` в AppBar (light/dark). Ширину окна десктопа менять вокруг **840dp** для проверки адаптива.

## Сценарии валидации

### A. Реальная композиция стека чата (FR-008 — снятие заглушки M3)
1. Галерея → **5.1 Chats list** (routeDemo).
2. **Мобайл (узко):** тап по чату → открывается **реальная лента 5.2** (не `RoutePlaceholderPage`). **Десктоп (широко):** выбор строки → реальная лента в **thread-pane** (highlight без push), persistent ThreadHeader.
3. В ленте: тап на имя (мобайл AppBar) / info-кнопку (десктоп ThreadHeader) → **5.4 Chat card** (мобайл push / десктоп right side-sheet 380).
4. Тап на file-chip в сообщении → **5.3 File view** (мобайл push / десктоп lightbox 520). Из 5.4 тап по файлу → тоже 5.3.
- **Ожидание:** стек `5.1 → 5.2 → 5.3/5.4` полностью реальный; плейсхолдеров ленты нет.

### B. 5.2 Chat thread — состояния и optimistic send
1. Галерея → **5.2** (routeDemo, sample chat).
2. **Filled:** свои справа (`primaryContainer`), чужие слева (`surfaceContainerHigh`); group-by-author (один author-header на группу чужих); время `HH:mm`; date-separator'ы (Today/Yesterday/`12 May`); ранняя system-line `Chat created by …`.
3. **Send:** ввести текст / нажать attach (no-op picker → draft-chip над composer) → send активна → тап send → сообщение появляется `pending` (часики) → `sent` (галочка). Очистка поля/draft.
4. **Send-error** (debug-переключатель `send-error`): сообщение `error` (красный `error_outline`) → тап по нему → retry.
5. **Loading-older:** скролл к началу → спиннер сверху, подгрузка старых.
6. **Empty / Offline / Fatal** (debug): system-line + empty `chatBubble`; `MaterialBanner` `No connection`; Fatal → 3.1.
- **Ожидание:** все состояния `chat.md` воспроизводимы; reverse-список; статусы только у своих.

### C. 5.3 File view — загрузка и сохранение
1. Галерея → **5.3** (routeDemo, sample file) или из 5.2/5.4.
2. **Loading:** `LinearProgressIndicator` с определённым % (фейк), `Save`/`Download` disabled.
3. **Loaded:** progress скрыт; крупный глиф типа + имя + размер (`2.4 MB`); `Save` enabled → тап → snackbar `Saved to Downloads` (no-op).
4. **Десктоп:** lightbox-`Dialog` 520 (`Downloading… N%` / `Download`); close/scrim → возврат.
5. **Inline-error** (debug): snackbar с retry.
- **Ожидание:** превью содержимого нет (только глиф); адаптив push ↔ lightbox.

### D. 5.4 Chat card — файлы List/Grid
1. Галерея → **5.4** (routeDemo) или из 5.2.
2. **Loaded-List:** header (аватар 56 + имя) + секция `Files` + строки (глиф+имя+размер).
3. **Grid:** `SegmentedButton` List→Grid → квадратные тайлы (мобайл ~3 кол / десктоп 2 кол).
4. **Empty-files** (debug/sample): empty `folderOpen` + `No files yet` / `Files sent in this chat will appear here.` (header виден).
5. **Десктоп:** right side-sheet 380 (`Details` + аватар + имя + Files); тап по файлу → 5.3 lightbox.
6. Read-only: нет edit/mute/pin/report; long-press — no-op.
- **Ожидание:** все состояния `chat-card.md`/`09-drawer` воспроизводимы.

### E. Адаптив (width-driven, 840dp)
- Узкое окно десктопа = мобильный лейаут (5.2 fullscreen, 5.3 push, 5.4 push); широкое = thread-pane / lightbox / side-sheet. Без `Platform`-проверок.

## Тесты и гейт

```bash
make test FILE=test/presentation/pages/chat_thread_page/        # widget + bloc_test (paging, optimistic send)
make test FILE=test/presentation/pages/chat_card_page/          # widget + bloc_test (list/grid/empty)
make test FILE=test/presentation/pages/file_view_page/          # widget (без bloc_test)
make test FILE=test/general/formatters/file_size_formatter_test.dart
make golden-update FILE=test/presentation/...                    # локально (Apple Silicon/macOS) — сгенерировать baselines
make golden-verify                                              # сверить goldens
make gate                                                        # generate → format → analyze → test (goldens исключены) — ЗЕЛЁНЫЙ перед сдачей
```

- Golden — `*_golden_test.dart` + `@Tags(['golden'])`; widget/unit — без тега. Харнес `pumpApp` обязателен. Прогресс/анимация — `settle: false`.
- DoD экрана (roadmap §5): оба лейаута, все состояния на мок, токен-дисциплина, доступ из Галереи в light/dark, бэкенд-заглушки помечены `// TODO(backend):`, golden+widget тесты, `make gate` зелёный.

## Точки замены (Фаза 2)

`// TODO(backend):` — реальный транспорт сообщений (`MessageRepository`/`GetMessagesApi`/`SendMessageApi`), реальная идентичность (`IdentityMockData` → реальный `currentUserId`), реальный file picker (`file_picker`), скачивание/кэш и сохранение в Downloads (`file_saver`/`path_provider`), реальные файлы чата (`getChatFiles`).
