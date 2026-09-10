# 5.4 Карточка чата

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 5.4 закрыты 2026-05-29.

## Назначение

Экран информации о конкретном чате. Показывает имя чата, секцию `People` и список вложений. **Метаданных (создатель, дата создания, счётчики, активность) не показывает**: они существуют в системе (event «Chat created» отображается inline в ленте 5.2, см. 5.2 Q11), но на 5.4 не выводятся. **Описания у чата нет** (см. 6.1 Q1).

Экран **read-only**: имя чата не редактируется (фиксируется при создании в 6.1). Действий (mute / pin / report / edit) нет.

## Контекст и переходы

- **Откуда:** 5.2 Лента чата — тап на имя чата в AppBar.
- **Куда:**
  - Back / back-стрелка → возврат в 5.2.
  - **5.3 Просмотр файла** — тап на файл в списке вложений.
  - **3.1 Универсальный экран ошибки** — fatal-сценарии.

## Лейаут

Material Scaffold; адаптируется под тему. Сверху вниз:

1. **AppBar (M3):** back-стрелка слева; **title — имя чата**.
2. **Body:** прокручиваемая column:
   - **Header:** имя чата (крупно).
   - **People section** (см. ниже): заголовок `People`, одна строка — сам человек, — под ней **выключенная** кнопка `Invite a person` с подписью `Available in a future version`.
   - **Files section:**
     - заголовок `Files` + переключатель **List / Grid** (`SegmentedButton`);
     - **List:** `ListTile`-ы; каждая ячейка — иконка типа (по маппингу из [overview.md / Файлы](../overview.md#файлы-иконки-типов-без-превью)) + имя файла + размер;
     - **Grid:** ~3 колонки, квадратные тайлы, gap `space/2`; в каждом — та же иконка типа + имя (truncate) + размер. Превью содержимого нет (согласовано с 5.3);
     - либо empty state (иллюстрация + текст), если вложений нет.

## Секция `People` (фаза 037)

**Это представление, а не ростер.** Настоящего состава участников у чата нет и появиться ему пока неоткуда: сервер принадлежит одному человеку, чат создаётся локально, а всё, что между разными людьми, уйдёт на relay-сервер, протокол которого не спроектирован ([Q13](../../../client-backend/open-questions.md)). Секция показывает **единственного человека этого сервера** — того же, чьё имя стоит в 7.1, — и читает его из уже существующего резолвера личности. Ни новой сущности, ни поля в модели чата, ни хранения она не заводит.

Состав:

- заголовок секции `People`;
- **ровно одна строка** — сам человек: сгенерированный аватар (инициалы + хеш-цвет, как у чатов) и его текущий label. Пустой секции не бывает: человек есть всегда;
- под строкой — **всегда неактивная** кнопка `Invite a person`;
- под кнопкой — подпись `Available in a future version`.

Нажатие на кнопку не даёт ничего: ни экрана, ни снекбара, ни ошибки. Подпись намеренно **не упоминает relay** — это внутренний термин, человеку у экрана он ничего не объясняет; формулировка обещает будущее, а не оправдывается за настоящее.

**Обе ширины.** Секция стоит между header'ом и `Files` и на мобильном fullscreen-push, и в десктопном side-sheet 380 — та же вёрстка, тот же порядок. Когда придёт relay, сюда ляжет настоящий состав, и вёрстка под него уже будет.

## Состояния

| Состояние | Описание |
|---|---|
| Initial-loading | Список файлов грузится. Centered `CircularProgressIndicator`. |
| Loaded | Header + People section + Files section отображаются. |
| Empty (files) | Файлов нет. **Empty state**: иллюстрация + текст в области Files section. Header и People section при этом остаются видны. |
| Offline / Inline-error | Не удалось загрузить — `MaterialBanner` сверху (persistent, см. [overview.md / Уровни ошибок](../overview.md#уровни-ошибок-и-обратной-связи)). |
| Fatal | Передача в 3.1 (embedded). |

## Взаимодействия

- **Тап на файл (ячейка List/Grid)** → 5.3.
- **Тап на переключатель `SegmentedButton`** → переключение List ↔ Grid.
- **Тап на `Invite a person`** → ничего: кнопка неактивна. Многократные нажатия тоже ничего не делают.
- **Тап на строку человека** → no-op: экрана профиля в NOX нет.
- **Тап на back** → возврат в 5.2.
- **Long-press на имя / файлах** — no-op на этом этапе.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с back-стрелкой и title = chat name; адаптируется под тему.
- `SingleChildScrollView` + `Column` (или `CustomScrollView` со sliver-ами).
- `SegmentedButton` (M3, single-select) — переключение List ↔ Grid.
- `ListView.builder` (List) и `GridView.builder` (Grid) — Files section; ячейка с иконкой типа (общий маппинг), именем и размером.
- `CircularProgressIndicator` — Initial-loading.
- Empty-state widget (иллюстрация + текст).
- `MaterialBanner` (M3) — persistent inline-error / offline.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar back tooltip | `Back` |
| AppBar title | (имя чата, динамически) |
| People section title | `People` |
| Invite button | `Invite a person` (всегда disabled) |
| Invite caption | `Available in a future version` |
| Files section title | `Files` |
| Files view toggle: List | `List` |
| Files view toggle: Grid | `Grid` |
| Files empty title | `No files yet` |
| Files empty message | `Files sent in this chat will appear here.` |
| Inline-error (network) | `Could not load chat info. Check your connection and try again.` |

## Принятые решения (Q1–Q9)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | AppBar | Имя чата как title |
| Q2 | Edit name / description | Read-only (фиксируются при создании в 6.1) |
| Q3 | Mute action | Нет |
| Q4 | Pin action | Нет |
| Q5 | Report action | Нет |
| Q6 | Files section UI | List / Grid через `SegmentedButton`; ячейка = иконка типа + имя + размер (без превью) |
| Q7 | Files фильтры | Все вложения вместе, без фильтров по типу |
| Q8 | Files empty state | Иллюстрация + текст |
| Q9 | Stats / метаданные | Не показываем (creator/date — только inline-событием в 5.2) |
| — | Секция `People` (фаза 037) | Представление, а не ростер: одна строка — сам человек, читается из резолвера личности; новой сущности и хранения не заводится |
| — | Кнопка приглашения (фаза 037) | `Invite a person` **всегда disabled**, под ней подпись `Available in a future version`; нажатие не даёт ничего. Обе ширины |

## Десктоп-раскладка (этап M4, сверено с корпусом)

> Добавлено при реализации M4. Сведено с `nox-desktop-screens/screens/09-drawer.md`.

- Десктоп (`>= 840dp`): карточка — **правый side-sheet 380** (`showRightSideSheet` / `AppSideSheetWidget`) со scrim поверх ленты; открывается из info-действия ThreadHeader (5.2 desktop). Заголовок `Details` + close, аватар + имя, секция `People` (строка человека + выключенная кнопка с подписью), секция Files (List / Grid, Grid — **2 колонки**). Тап по файлу → 5.3 (lightbox).
- Мобайл — fullscreen push (AppBar back + имя), тот же порядок секций, Grid — **3 колонки**.
- Форма (правый drawer, не detail-pane swap) — owner-санкция (Clarifications M4; закрывает roadmap Q6).
