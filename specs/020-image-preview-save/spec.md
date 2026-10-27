# Feature Specification: Inline image thumbnails + full-screen viewer + real save (F4 + F2)

**Feature Branch**: `020-image-preview-save`

**Created**: 2026-07-26

**Status**: Draft

**Input**: Owner request — в переписке показывать миниатюру изображения; прочие типы как есть (type-icon чип); тап по изображению → full-screen. Плюс F2 (реальный Save выбранного файла).

## Контекст и цель

Сегодня **все** вложения в треде рендерятся type-icon чипом (`AppFileChipWidget`) — «file content previews (type-icon chips only)» было locked-решением `overview.md`. **Owner-запрос 2026-07-26 ревизует его для изображений:** image-вложение с реальным локальным файлом рендерит **инлайн-миниатюру** в бабле, тап → **full-screen просмотр** (zoom/закрытие); прочие типы — чип как есть. Параллельно **F2**: file-view (5.3) Save реально копирует выбранный файл (был мок-snackbar).

Обе части опираются на **локальный путь** выбранного файла: F1-picker сейчас сохраняет только name/size/type. Эта фича добавляет `localPath` (устройство-локальный путь `XFile`) во вложение — по нему рендерится миниатюра и копируется файл. `localPath` — UI-фазовая device-local деталь: у сеяных/бэкенд-вложений его нет (→ чип); реальный бэкенд заменит его на URL/ref.

**Мультиплатформенно (mobile + desktop).** Реального аплоада/даунлоада нет — только локальные байты выбранного файла.

## Clarifications

### Session 2026-07-26

- Q: Где живёт `localPath` и персистится ли он? → A: **На `MessageAttachment` (домен), персистится в Sembast** (`MessageEntity.attachmentLocalPath` + `MessageMapper`). НЕ на wire-вложении (S4): сеяные вложения не имеют локального файла, так что wire→model даёт `localPath=null` для них. Отправленное юзером image-вложение несёт `localPath` (из picker'а) → эхо `SendMessageApi` его сохраняет → персистится в Sembast → переживает рестарт (пока файл существует).
- Q: Что если `localPath` пуст/файл удалён (stale после рестарта)? → A: **Graceful fallback** — миниатюра при отсутствии/недоступности файла падает обратно на type-icon чип; Save при отсутствии файла — недоступен/ошибка-snackbar, не краш.
- Q: Нужен ли голден для full-screen вьювера (контент — юзерское изображение, недетерминирован)? → A: **Вьювер освобождён от голдена** (image-content-dependent, как brand-fixed splash); покрывается widget-тестом (открытие/закрытие/наличие `InteractiveViewer`). Тред-голдены не меняются (seed несёт PDF-чип, не image). Композер-драфт с picked-image в голденах не участвует.
- Q: Что нужно для реального Save на macOS? → A: **`com.apple.security.files.user-selected.read-write`** (апгрейд с read-only) — write в user-picked папку через `file_selector` `getSaveLocation`. Чтение локального файла (`Image.file`) доп. конфигурации не требует.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Image-вложение рендерит инлайн-миниатюру (Priority: P1)

Image-вложение (`FileType.image`) с реальным локальным файлом показывает в бабле миниатюру самого изображения; прочие типы (pdf/doc/…) — type-icon чип как раньше; отсутствующий/недоступный файл → чип-fallback.

**Why this priority**: Ядро owner-запроса — видеть картинку, а не иконку.

**Independent Test**: бабл с image-вложением (валидный локальный путь) содержит `Image`-виджет; бабл с pdf-вложением содержит `AppFileChipWidget`; image-вложение без `localPath` → чип.

**Acceptance Scenarios**:

1. **Given** отправленное image-вложение с валидным `localPath`, **When** рендерится бабл, **Then** показана миниатюра (не type-icon чип), обрезанная/вписанная в бабл-ширину, скруглённая.
2. **Given** pdf/doc/архив-вложение, **When** рендерится бабл, **Then** показан type-icon чип (без изменений).
3. **Given** image-вложение без `localPath` (сеяное) или файл недоступен, **When** рендерится бабл, **Then** fallback на type-icon чип (не битая картинка, не краш).

---

### User Story 2 — Тап по изображению → full-screen просмотр (Priority: P1)

Тап по инлайн-миниатюре открывает изображение на весь экран с возможностью зума (pinch/scroll) и закрытия (back/close/tap-scrim).

**Why this priority**: Вторая половина owner-запроса — «оно должно открываться полностью full screen».

**Independent Test**: тап по миниатюре пушит/открывает full-screen вьювер (`InteractiveViewer` + close); закрытие возвращает в тред.

**Acceptance Scenarios**:

1. **Given** инлайн-миниатюра, **When** по ней тапнули, **Then** открывается full-screen вьювер того же изображения (mobile push / desktop dialog-lightbox), с `InteractiveViewer` (зум) и close/back.
2. **Given** открытый вьювер, **When** нажали close/back (или tap по scrim на десктопе), **Then** возврат в тред.
3. **Given** файл вьювера недоступен, **When** вьювер строится, **Then** graceful fallback (плейсхолдер/сообщение), не краш.

---

### User Story 3 — File-view (5.3) Save реально копирует файл (F2) (Priority: P2)

File-view Save (после мок-«download») реально копирует файл из `localPath` в выбранную пользователем папку (`file_selector` `getSaveLocation`), а не только показывает snackbar.

**Why this priority**: F2 — owner-override; теперь достижимо, т.к. есть `localPath`.

**Independent Test**: Save с валидным `localPath` пишет копию в выбранную папку (замоканный save-location) и подтверждает; без `localPath`/отменённого диалога — no-op/ошибка, не краш.

**Acceptance Scenarios**:

1. **Given** файл с валидным `localPath` и `_cached==true`, **When** Save → выбрана папка, **Then** байты файла записаны в выбранный путь + подтверждение (snackbar).
2. **Given** отменённый save-диалог, **When** Save, **Then** ничего не записано, композер/вью не тронуты.
3. **Given** вложение без `localPath` (сеяное/бэкенд-TBD), **When** Save, **Then** снова мок-подтверждение (реальных байтов нет — честный UI-фазовый fallback), не краш.

---

### Edge Cases

- **Stale `localPath` после рестарта** (файл удалён/перемещён) — миниатюра → чип-fallback; Save → ошибка/мок-fallback.
- **Пустой/whitespace `localPath`** — трактуется как отсутствие (чип, не миниатюра).
- **Не-image с `localPath`** — всё равно чип (миниатюра только для `FileType.image`).
- **Голдены** — тред-seed несёт PDF-чип (не image) → тред-голдены не меняются; вьювер освобождён от голдена.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `MessageAttachment` MUST нести nullable `localPath`; F1-picker (`FilePickerServiceImpl`) MUST сохранять `XFile.path` в `PickedFile.path` → во вложение-драфт.
- **FR-002**: `localPath` MUST персистироваться в Sembast (`MessageEntity.attachmentLocalPath` + `MessageMapper`) и переживать рестарт; НЕ добавляется на wire-вложение (сеяные не имеют файла).
- **FR-003**: Image-вложение (`FileType.image`) с непустым `localPath` и **существующим** файлом MUST рендерить инлайн-миниатюру (fit/clip, скругление) вместо type-icon чипа; иначе (не-image / нет пути / файл недоступен) — чип.
- **FR-004**: Тап по миниатюре MUST открывать full-screen просмотр (`InteractiveViewer` зум + close/back; mobile push / desktop lightbox), закрытие → возврат в тред.
- **FR-005**: File-view (5.3) Save MUST при валидном `localPath` копировать байты файла в выбранную (`file_selector` `getSaveLocation`) папку + подтверждение; отмена → no-op; отсутствие пути/файла → graceful мок-fallback/ошибка (не краш).
- **FR-006**: macOS MUST получить `files.user-selected.read-write` entitlement (для write при Save).
- **FR-007**: Fallback MUST быть graceful везде: недоступный файл → чип/плейсхолдер/мок-подтверждение, никогда не краш и не битая картинка.
- **FR-008**: Прочее поведение MUST сохраниться: не-image вложения, сеяный тред, чипы, тред-голдены — без изменений.

### Key Entities

- **MessageAttachment** *(edit)* — + `String? localPath` (device-local; null для сеяных/бэкенд).
- **PickedFile** *(edit)* — + `String? path`.
- **MessageEntity (Sembast)** *(edit)* — + `attachmentLocalPath`.
- **Full-screen image viewer** *(new)* — `InteractiveViewer` + close, adaptive (push/lightbox).

## Success Criteria *(mandatory)*

- **SC-001**: Image-вложение с валидным путём показывает миниатюру; не-image / нет пути / недоступный файл → чип — 3 ветки покрыты.
- **SC-002**: Тап по миниатюре открывает full-screen вьювер; закрытие возвращает в тред.
- **SC-003**: Save с валидным путём пишет копию в выбранную папку; отмена → no-op; нет пути → мок-fallback — покрыто.
- **SC-004**: `localPath` переживает рестарт (персист в Sembast) — покрыто mapper/repo-тестом.
- **SC-005**: 0 регрессий не-image рендеринга; тред-голдены без изменений; `make gate` + `make golden-verify` зелёные; macOS-сборка (read-write entitlement) собирается.
- **SC-006**: Никаких крашей на stale/missing файлах (graceful fallback) — покрыто.

## Assumptions

- `Image.file(File(localPath))` для миниатюры/вьювера; `errorBuilder` → чип/плейсхолдер fallback (недоступный файл).
- Существование файла проверяется дёшево (`File(path).existsSync()` для рендер-решения) — приемлемо для локального пути в UI-фазе.
- `file_selector` `getSaveLocation` для выбора папки/имени; запись через `dart:io` `File(dest).writeAsBytes(File(src).readAsBytes())` (или `copy`).
- Wire-вложение (S4) не меняется — сеяные вложения без `localPath`.

## Out of Scope

- Реальный upload/download байтов по сети (только локальный файл выбранного/отправленного вложения).
- Превью для не-image типов (pdf/video-thumbnail и т.п.) — только image.
- Редактирование/кроп/шеринг изображения; множественный выбор.
- Изменение wire-контракта/бэкенда; кэш «скачанного» файла в 5.3 остаётся мок-таймером (реальный download — Phase 2/бэкенд).
