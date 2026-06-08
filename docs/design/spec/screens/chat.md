# 5.2 Лента чата

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 5.2 закрыты 2026-05-29.

## Назначение

Экран конкретного чата. Просмотр истории сообщений и отправка новых: **текстовых сообщений** и **файлов**. Каждое сообщение подписано именем автора (label).

## Контекст и переходы

- **Откуда:** 5.1 Список чатов — по тапу на элемент списка.
- **Куда:**
  - **5.3 Просмотр файла** — тап на файл-chip в сообщении.
  - **5.4 Карточка чата** — тап на имя чата в AppBar.
  - Back / back-стрелка → 5.1.
  - **3.1 Универсальный экран ошибки** — fatal-сценарии.

## Лейаут

Material Scaffold с `resizeToAvoidBottomInset: true`; адаптируется под тему. Сверху вниз:

1. **AppBar (M3):** back-стрелка слева; центральный title — **только имя чата** (тап → 5.4).
2. **Body:** обратный (`reverse: true`) `ListView` сообщений — новые внизу, старые сверху. История подгружается **автоматически** при скролле вверх (infinite scroll до достижения порога). Нижняя панель шелла на этом экране **не видна** (5.2 — pushed поверх 4.1).
3. **Bottom — composer.**

### Composer

- **Многострочное растущее** поле ввода (`maxLines: 4–6`, далее внутренний скролл).
- Слева/в поле — иконка **attach** (paperclip).
- Справа — иконка **send** (paper-plane).
- **Правило send:** кнопка send **активна**, если поле непустое **или** есть прикреплённый файл; иначе disabled.
- **Прикреплённый, но ещё не отправленный файл** показывается над/в композере как chip (иконка типа + имя + размер + кнопка удаления `×`) — по правилам file-chip из [overview.md / Файлы](../overview.md#файлы-иконки-типов-без-превью). Можно прикрепить файл и/или ввести текст в одном сообщении.

### Сообщения (item)

- **Стиль bubble:** Material 3 standard — **rounded** corners, без «хвоста».
- **Свои vs чужие** — разное выравнивание (right / left) и разный фон bubble: свой — `primaryContainer` / `onPrimaryContainer`, чужой — `surfaceContainerHigh` / `onSurface` (см. [design-system §9.2](../design-system.md)). Принадлежность («свои/чужие») и группировка определяются по **идентификатору** автора (стабильный ключ), не по label.
- **Автор:** для чужих сообщений над группой — header с **текущим** label автора (re-fetched на момент рендера; per-author аватаров нет — см. [overview.md](../overview.md#generated-avatar-для-чатов)).
- **Group-by-author:** подряд идущие сообщения одного автора (по идентификатору) **объединяются** — один header сверху группы.
- **Время:** **на каждом сообщении** (`HH:mm`) — в углу bubble. Date-separators между днями — по лестнице из [overview.md / Форматы времени](../overview.md#форматы-времени-и-даты).
- **Файлы-вложения:** chip (иконка типа + имя + размер), **без превью содержимого**; тап → 5.3.
- **Статус (только для своих, в углу bubble):** см. таблицу ниже. **delivered / read не используются** — в открытом пространстве нет фиксированного получателя (см. [overview.md / Внутри чата](../overview.md#внутри-чата)).
- **Системные события:** в начале истории — inline «Chat created by `<username>`». Других системных событий нет (нет join / leave).

#### Иконки статуса своего сообщения

| Статус | Когда | Глиф | Цвет |
|---|---|---|---|
| `pending` | отправка в процессе | `Icons.schedule` (часики) | `onSurfaceVariant` |
| `sent` | принято сервером | `Icons.check` (одна галочка) | `onSurfaceVariant` |
| `error` | не удалось отправить | `Icons.error_outline` | `ColorScheme.error` |

## Состояния

| Состояние | Описание |
|---|---|
| Initial-loading | Первая загрузка истории. Centered `CircularProgressIndicator` (как в 5.1). |
| Empty | В чате нет сообщений. Системная строка «Chat created by …» показывается всегда и **сообщением не считается**; **Empty state** (иллюстрация + заголовок + текст) рисуется ниже неё. |
| Filled | Сообщения отображаются. |
| Loading-older | Подгружается история наверх (auto). Сверху списка — `CircularProgressIndicator`. |
| Sending | Сообщение появляется в ленте сразу со статусом `pending` → `sent`. |
| Send-error | Не удалось отправить. Статус `error` на сообщении; тап → retry. |
| Offline | Нет соединения — постоянный `MaterialBanner` `No connection` сверху (см. [overview.md / Offline](../overview.md#offline--нет-соединения)). Отправка офлайн → `pending` до восстановления. |
| Fatal | Передача в 3.1 (embedded). |

## Взаимодействия

- **Скролл наверх** → auto-load старых сообщений (без явного жеста).
- **Тап на файл-chip** → 5.3.
- **Тап на имя чата в AppBar** → 5.4.
- **Тап в поле композера** → клавиатура поднимается; поле растёт по высоте (до лимита, далее внутренний скролл).
- **Тап на attach** → системный file picker (любой тип файла, включая фото). Выбранный файл → chip в композере.
- **Тап на send** → отправка текста и/или прикреплённого файла. Disabled, если нет ни текста, ни файла.
- **Тап на сообщение в Send-error** (или на его статус-иконку) → retry отправки.
- **Long-press на сообщение** — no-op на этом этапе (вне scope: reactions, edit, delete).

## Material-компоненты

- `Scaffold` с `resizeToAvoidBottomInset: true`.
- `AppBar` (M3) с back-стрелкой и кастомным title; адаптируется под тему.
- `ListView` (`reverse: true`) с кастомными message-bubble widgets (M3 rounded, цвета из `ColorScheme`).
- Композер: `TextField` (M3, `maxLines: 4–6`) + `IconButton` (attach) + `IconButton` (send, paper-plane). File-chip — `Chip`/`InputChip` с иконкой типа.
- `Icon` — статусы сообщения (см. таблицу).
- `CircularProgressIndicator` — Initial-loading и Loading-older.
- `MaterialBanner` (M3) — offline.
- Empty-state widget (иллюстрация + текст).

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar back tooltip | `Back` |
| Composer placeholder | `Message` |
| Attach tooltip | `Attach` |
| Send tooltip | `Send` |
| Remove attachment tooltip | `Remove` |
| Send-error tooltip | `Tap to retry` |
| Empty state title | `No messages yet` |
| Empty state message | `Send the first one.` |
| System event (chat created) | `Chat created by {username}` |
| Offline banner | `No connection` |

(Date-separators — по лестнице из overview; не дублируются здесь.)

## Принятые решения (Q1–Q11)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | AppBar | Только имя чата (back-стрелка + name); тап → 5.4 |
| Q2 | Подгрузка старых | Auto-load при скролле (infinite scroll) |
| Q3 | Стиль bubble | M3 standard (rounded, без хвоста) |
| Q4 | Group-by-author | Группируем по идентификатору; один header у группы |
| Q5 | Формат времени | `HH:mm` на каждом сообщении + date-separators (лестница в overview) |
| Q6 | Композер: формат поля | Многострочное растущее; send активна при тексте или вложении |
| Q7 | Attach UI | Одна иконка → системный file picker; выбранный файл → chip в композере |
| Q8 | Send icon | Paper-plane |
| Q9 | Empty state | Иллюстрация + текст |
| Q10 | Status сообщений | Только `sent` (+ `pending` / `error`); **delivered / read не используются** |
| Q11 | Системные события | Только inline «Chat created by `<username>`» в начале истории |
| — | Вложения | File-chip (иконка + имя + размер), без превью содержимого |
| — | Ключ автора | Идентификатор (стабильный), label — отображаемый |
