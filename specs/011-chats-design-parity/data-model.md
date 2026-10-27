# Data Model: Chats list — сверка с дизайном и golden-покрытие

Фича — presentation-only; новых доменных моделей/таблиц нет. Ниже — сущности отображения и их инварианты, релевантные для реализации и golden-покрытия.

## Сущности

### ChatRow (строка чата) — существующая, без изменений модели

Источник: `ChatModel` (domain) → `AppChatItemWidget`. Network-only mock-репозиторий.

| Поле | Тип | Описание / инвариант |
|---|---|---|
| `name` | String | Имя чата (≤64, неогр. charset); 1 строка, `ellipsis`. |
| `preview` | String | Превью последнего сообщения (`Author: text`); 1 строка, `ellipsis`. |
| `time` | String | Относительное время (`DateFormatter.relative`): `now` / `5 min` / `2 h` / `Yesterday`. |
| `unread` | int | Счётчик непрочитанных; `0` → бейдж скрыт; `>99` → `99+`. |
| avatar | derived | `AppAvatarWidget(name)`: цвет по `noxAvatarColor(name)`, инициалы по `noxInitials(name)` (правило чатов, **не меняется**). |

**Визуальные инварианты (по дизайну):** непрочитанная строка — имя `w600`, превью `onSurface`, время `primary`, бейдж виден; прочитанная — `w500`, превью/время `onSurfaceVariant`, без бейджа. minHeight `chatRowMinH`. На desktop выбранная строка обёрнута inset-пилюлей `secondaryContainer` (радиус `lg`, гориз. margin `s8`).

### AccountAvatar (аккаунт-аватар) — НОВАЯ сущность отображения (desktop-only)

Источник: `SessionModel.label` (через `sessionRepository.readSession()`), fallback `User7421`.

| Поле | Тип | Описание / инвариант |
|---|---|---|
| `label` | String | Display-label пользователя (`[A-Za-z0-9._-]`, ≤32). Источник хэш-цвета фона. |
| `initials` | String? | `noxAccountInitials(label)` — см. правило ниже. `null` → glyph-fallback `forumFill`. |
| фон | derived | `noxAvatarColor(label)` (та же палитра, что у чатов). |
| target | action | Тап → `Settings` tab + секция `Account`. |
| visibility | derived | Видим **только** в широкой (rail) вёрстке; в bottom-bar отсутствует. |

#### Правило `noxAccountInitials(label)` (pure util)

1. Токенизация: `label.trim().split(RegExp(r'[\s._-]+'))`, отбросить пустые токены.
2. Для каждого токена взять первую **алфавитно-цифровую** букву (`[A-Za-z0-9]`).
3. `≥2` токенов → буква первого + буква последнего токена (uppercase) = **2 буквы**.
4. `1` токен → его первая буква (uppercase) = **1 буква**.
5. Нет валидных токенов/букв → `null` (виджет рисует glyph-fallback).

| Вход | Выход |
|---|---|
| `User7421` | `U` |
| `john.doe` | `JD` |
| `john_doe_smith` | `JS` |
| `a-b-c` | `AC` |
| `Alice` | `A` |
| `nox.core.team` | `NT` |
| `` / `...` / `__` | `null` |

## Состояния экрана (для функционального + golden покрытия)

`ChatsListState` (Freezed): `Initializing` / `Initialized` / `Error`. Видимые UI-состояния, которые покрываются:

| Состояние | Условие | Mobile (`_narrow`) | Desktop (`_wide`) |
|---|---|---|---|
| `filled` | `Initialized`, есть items | список строк | список + detail (no-selection / selected) |
| `loading` | `Initializing` | центр. спиннер | спиннер в list-панели |
| `empty` | `Initialized`, items пуст, не поиск | empty-state (`No chats yet`) | empty-state в list-панели |
| `offline` | `Initialized.isOffline` | баннер `No connection` | баннер в панели(ях) |
| `inline-error` | `Initialized.hasLoadError` | баннер `Could not load chats. Pull to refresh.` | то же |
| `search` | `isSearching`, есть совпадения | отфильтрованный список | то же |
| `search-empty` | `isSearching`, нет совпадений | `No chats found` | то же |
| `error` (fatal) | `Error` | `AppErrorWidget` (try again) | то же |
| `no-selection` | desktop, `selectedChatId == null` | — | empty-state `Select a chat` |
| `selected` | desktop, выбрана строка | — | подсветка строки + тред в detail |

## Сигналы координации shell ↔ страницы (не модели данных, а контракты состояния)

| Сигнал | Тип | Владелец | Потребитель | Назначение |
|---|---|---|---|---|
| `scrollToTop` | `ValueListenable<int>` | `TabBarShell` | `ChatsListPage` | существующий — скролл списка вверх по ре-тапу Chats |
| `jumpToAccount` | `ValueListenable<int>` | `TabBarShell` | `SettingsRootPage` | НОВЫЙ — по тапу аккаунт-аватара выбрать секцию `Account` |
| `accountLabel` | `String?` | `TabBarShell` (one-shot `sessionRepository`) | `AppNavigationRailWidget` | НОВЫЙ — label для инициалов/цвета аватара |

> **`jumpToAccount` — desktop-only по эффекту (U1a).** Аккаунт-аватар существует только в widget-rail (широкая вёрстка), значит бамп происходит исключительно на широком окне. На узком (mobile) `SettingsRootPage` — плоский список без `_selected`-секций, поэтому слушатель сигнала там безопасно no-op (карточка идентичности и так на вершине списка). Передавать `jumpToAccount` в mobile-ветку не требуется.

> **Терминология (I1).** Каноничный термин в прозе — **label** (отображаемое имя пользователя). В коде он же фигурирует как `SessionModel.label` (источник) и `SettingsRootState.name` (display-поле страницы). Это намеренный маппинг, а не дрейф: `noxAccountInitials`/аватар берут именно `label`.

## Что НЕ меняется

- `ChatModel`, `ChatsListBloc`, `ChatsListEvent/State`, репозиторий чатов — без изменений (только визуал страницы).
- `noxInitials` (правило аватаров чатов) — без изменений.
- `SettingsRootBloc` — без изменений (только страница принимает сигнал `jumpToAccount`).
