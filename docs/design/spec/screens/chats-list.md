# 5.1 Список чатов

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 5.1 закрыты 2026-05-29.

## Назначение

Главный экран таба «Chats» в основном шелле (4.1). Показывает **глобальный список всех чатов** (открытое общее пространство — см. [overview.md / Чаты](../overview.md#чаты)). Точка входа в конкретный чат (5.2) и в создание нового (6.1, через центральную `+`).

## Контекст и переходы

- **Откуда:** 4.1 Tab bar shell (таб «Chats») — при первом открытии и при возврате на таб.
- **Куда:**
  - **5.2 Лента чата** — по тапу на элемент списка.
  - **6.1 Создание чата** — через центральную `+` (поток обрабатывается шеллом 4.1, не самим списком).
  - **3.1 Универсальный экран ошибки** — при fatal-сценариях загрузки.

## Лейаут

Material Scaffold внутри `Tab bar shell` (4.1). Сверху вниз:

1. **AppBar (M3):** с wordmark `NOX`; адаптируется под тему.
2. **Постоянная M3 `SearchBar`** под AppBar для поиска по имени чата.
3. **Body:** `ListView.builder` с элементами чатов, обёрнут в `RefreshIndicator` (pull-to-refresh).
4. **Bottom:** нижняя панель — часть `4.1 Tab bar shell` (рендерится шеллом).

### Элемент списка (item)

Каждый элемент содержит (слева направо):

- **Аватар** — generated avatar чата по правилам из [overview.md / Generated avatar](../overview.md#generated-avatar-для-чатов) (инициалы + хеш-цвет; fallback-иконка для не-латиницы/символов).
- **Колонка контента (растягивается):**
  - имя чата (header);
  - превью последнего сообщения (subtitle, ellipsis при переполнении).
- **Колонка справа (вертикальная):**
  - время последнего сообщения — **относительное**, по лестнице из [overview.md / Форматы времени](../overview.md#форматы-времени-и-даты) (`now`, `5 min`, `2 h`, `Yesterday`, `12 May`);
  - **unread badge** — число, считается **от последнего открытия чата этим устройством**; никогда не открытый чат бейджа **не имеет**; переполнение — `99+`.

## Состояния

| Состояние | Описание |
|---|---|
| Initial-loading | Первая загрузка. **Centered** `CircularProgressIndicator` в области body. |
| Empty | Чатов нет. **Empty state**: иллюстрация (из дизайн-системы) + заголовок + поясняющий текст. |
| Filled | Список чатов отображается. |
| Searching | В `SearchBar` непустой запрос; список фильтруется по имени в реальном времени. |
| Search-empty | По запросу ничего не найдено — надпись `No chats found` в области результата. |
| Offline | Нет соединения — постоянный `MaterialBanner` `No connection` сверху (под AppBar/SearchBar). Список показывает кэш. |
| Inline-error | Не удалось загрузить — `MaterialBanner` сверху с предложением обновить (pull-to-refresh / action). |
| Fatal | Передача в 3.1 (embedded). |

## Взаимодействия

- **Тап на элемент списка** → переход в 5.2.
- **Ввод в `SearchBar`** → фильтрация по имени чата в реальном времени.
- **Pull-to-refresh** (`RefreshIndicator`) → запрос актуального состояния списка.
- **Повторный тап по табу Chats** (в шелле) → скролл списка в начало.
- **Long-press на элемент** — **no-op** на этом этапе.
- **Сортировка** — фиксированная: по времени последнего сообщения. Переключателя пользователю нет.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с wordmark `NOX`; адаптируется под тему.
- `SearchBar` (M3) — постоянная строка под AppBar.
- `RefreshIndicator` оборачивает `ListView.builder`.
- `ListView.builder` с кастомным item widget.
- Generated-avatar widget (общая спека в overview).
- `Badge` (M3) с числом — unread; цветовая роль `ColorScheme.primary` (не дефолтный error-red). При N = 0 бейдж не рендерится, правая колонка остаётся выровненной по времени.
- `CircularProgressIndicator` (центрированный) — Initial-loading.
- `MaterialBanner` (M3) — offline / inline-error.
- Empty-state widget (`Column` с иллюстрацией + текст).

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar wordmark | `NOX` |
| Search placeholder | `Search` |
| Empty state title | `No chats yet` |
| Empty state message | `Tap + to create the first one.` |
| Search empty | `No chats found` |
| Offline banner | `No connection` |
| Inline-error (network) | `Could not load chats. Pull to refresh.` |

## Принятые решения (Q1–Q10)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | AppBar содержимое | Wordmark `NOX` |
| Q2 | Search UI | M3 `SearchBar` постоянная строка под AppBar |
| Q3 | Pull-to-refresh | Есть (`RefreshIndicator`) |
| Q4 | Long-press на элементе | Ничего |
| Q5 | Сортировка | Только default — по времени последнего сообщения |
| Q6 | Unread badge | Число; от последнего открытия устройством; never-opened — без бейджа; cap `99+`; роль `primary` |
| Q7 | Аватар чата | Generated avatar (общая спека в overview) |
| Q8 | Формат времени | Относительное (лестница в overview) |
| Q9 | Initial-loading | Centered `CircularProgressIndicator` |
| Q10 | Empty state | Иллюстрация + текст |

## Десктоп-раскладка (этап M3, сверено с корпусом)

> Добавлено при реализации M3. Сведено с `nox-desktop-screens/screens/01-chats.md`.

- Десктоп (`>= 840dp`) — **list-detail**: `NavigationRail` (шелл) + chat-list-pane ≈360 (pane-header + поле поиска) + thread-pane. Выбор строки подсвечивает её (`secondaryContainer`) и загружает ленту справа **без** навигационного push (выбор — view-state в `ChatsListBloc`, контейнер `AppListDetailWidget`).
- **Контент ленты (5.2) на этапе M3 — лёгкий плейсхолдер** «лента — в M4»; состояние no-selection — `Select a chat` / `Choose a conversation on the left, or press + to start a new one.`. Механика master-detail построена полностью; реальная лента 5.2 — этап M4.
- Офлайн/inline-error — баннер под поиском в list-pane; список показывает кэш.
