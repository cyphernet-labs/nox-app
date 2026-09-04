# 7.1 Корень настроек

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 7.1 закрыты 2026-05-29.

## Назначение

Главный экран таба «Settings» в основном шелле 4.1. Контейнер всех разделов настроек: блока имени пользователя, блока идентификатора, пунктов в подразделы 7.2–7.7, а также действия Logout. Отдельного экрана профиля нет (см. [overview.md / Основной шелл](../overview.md#основной-шелл)).

## Контекст и переходы

- **Откуда:** 4.1 Tab bar shell (третий таб «Settings»).
- **Куда:**
  - **7.2 Уведомления**, **7.3 Внешний вид**, **7.4 Язык**, **7.6 Terms**, **7.7 О приложении** — через `ListTile` секции (раздел Support вне scope).
  - **Edit имени** — inline на 7.1, без перехода.
  - **Show QR** — modal bottom sheet поверх 7.1.
  - Действие **Logout** (с `AlertDialog` подтверждения) → 1.1 Splash после полной очистки локальных данных (см. [overview.md / Настройки](../overview.md#настройки)).
  - **3.1 Универсальный экран ошибки** — fatal-сценарии.

## Лейаут

Material Scaffold внутри `Tab bar shell` (4.1). Сверху вниз:

1. **AppBar (M3):** `title: 'Settings'`; адаптируется под тему.
2. **Body:** прокручиваемый `ListView`:
   - **Identity card (Material Card):** визуально выделена.
     - **Блок имени**: label `Name` + текущее имя + edit-аффорданс (pencil-иконка). Тап превращает текстовую строку в inline `TextField`.
     - **Блок идентификатора (одна строка)**: label `Your ID` + masked text (`••••••••` — точки фиксированной длины 8) + action-row справа (`Show/Hide` toggle · `Copy` · `Show QR`). При раскрытии (`Show`) длинный идентификатор переносится по строкам (text wrap, monospace); action-row остаётся под текстом; `Hide` возвращает маску.
   - **Плоский список** `ListTile`-ов (без group-заголовков):
     - `Notifications` → 7.2;
     - `Appearance` → 7.3;
     - `Language` → 7.4;
     - `Terms` → 7.6;
     - `About` → 7.7;
     - `Log out` — последний пункт, в `ColorScheme.error`.

## Состояния

| Состояние | Описание |
|---|---|
| Initial-loading | Identity card показывает `CircularProgressIndicator` в позиции ID; список остальных пунктов уже доступен. |
| Loaded | Всё отображается. |
| Name-editing | Inline `TextField` активен в блоке имени; работает та же валидация, что в 2.3 (real-time uniqueness, charset Латиница + цифры + `-`, `_`, `.`, лимит 32). |
| QR-overlay | Открыт modal bottom sheet: drag-handle, заголовок, **QR на постоянном светлом фоне** (`brand/qr-surface` #FFFFFF, сканируем в обеих темах; токены — [design-system §9.10](../design-system.md)), quiet-zone, кнопка `Close`. Высота — wrap-content. Raw-идентификатор текстом в sheet **не показывается** (только QR-кодирование). |
| Logout-confirm | Открыт `AlertDialog` подтверждения. |
| Logout-loading | После confirm: кнопка `Log out` в диалоге → disabled + `CircularProgressIndicator`; диалог модален и не закрывается до завершения очистки и перехода в 1.1. |
| Inline-error | Не удалось выполнить действие; `SnackBar` (transient) либо `errorText` поля. |
| Fatal | Передача в 3.1. |

## Взаимодействия

- **Тап на `ListTile` секции** → push соответствующего подэкрана 7.2–7.7.
- **Тап на имя / pencil** → блок имени превращается в inline `TextField` с фокусом. Индикатора проверки занятости нет: имена людей не уникальны на этапе 1 (решение владельца 2026-09-02, см. [2.3](./set-username.md)), проверять нечего — решают только charset и длина, и решают сразу. **Save** — по Enter / Done или потере фокуса при валидном имени. При **invalid** — остаёмся в режиме edit с `errorText`, фокус не теряем. **Пустое поле** при сохранении → имя не меняется (у пользователя всегда есть label; очистить в null нельзя). Cancel — системный back, возврат к прежнему значению.
- **Тап на `Show/Hide`** → toggle между маской `••••••••` и raw-текстом идентификатора.
- **Тап на `Copy`** → копирование raw-идентификатора в буфер + snackbar `Copied to clipboard`.
- **Тап на `Show QR`** → modal bottom sheet (`showModalBottomSheet`): QR на светлом фоне (сканируемый в light/dark), drag-handle, `Close`; без текстового raw-ID. QR статичен (кодирует текущий идентификатор).
- **Тап на `Log out`** → `AlertDialog` с предупреждением о потере локальных данных. На confirm — очистка и переход в 1.1.

## Material-компоненты

- `Scaffold` внутри tab bar shell.
- `AppBar` (M3) с `title: 'Settings'`; адаптируется под тему.
- `ListView` / `Column` с секциями.
- `Card` (M3, **filled** variant) — обрамление блока идентичности.
- `ListTile` (M3) — пункты настроек и Logout (последний в `ColorScheme.error`).
- `IconButton` — `Show/Hide`, `Copy`, `Show QR`.
- `TextField` (M3) inline — редактирование имени.
- Modal bottom sheet (`showModalBottomSheet`, M3) — QR-overlay.
- `AlertDialog` (M3) — Logout confirmation.
- `CircularProgressIndicator` — Initial-loading в позиции ID.
- `SnackBar` (M3) — Copy и обратная связь.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `Settings` |
| Name block label | `Name` |
| Name edit tooltip | `Edit` |
| Identifier block label | `Your ID` |
| Identifier mask (default) | `••••••••` (8 точек, фиксированная длина) |
| Show identifier tooltip | `Show` |
| Hide identifier tooltip | `Hide` |
| Copy tooltip | `Copy` |
| Show QR tooltip | `Show QR` |
| QR bottom sheet title | `Your ID QR` |
| QR bottom sheet close | `Close` |
| Copy snackbar | `Copied to clipboard` |
| Notifications row | `Notifications` |
| Appearance row | `Appearance` |
| Language row | `Language` |
| Terms row | `Terms` |
| About row | `About` |
| Logout row | `Log out` |
| Logout dialog title | `Log out?` |
| Logout dialog message | `Your ID and local data will be removed from this device.` |
| Logout dialog confirm | `Log out` |
| Logout dialog cancel | `Cancel` |

## Принятые решения (Q1–Q9)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | AppBar | Title `Settings` |
| Q2 | Username edit UX | Inline на 7.1 |
| Q3 | Show QR UX | Modal bottom sheet |
| Q4 | Identifier block layout | Одна строка (label + masked + actions) |
| Q5 | Identifier mask | Точки фиксированной длины 8 (`••••••••`) |
| Q6 | Logout visual | `ListTile` в `ColorScheme.error` |
| Q7 | Сепарация блока идентичности | Material Card |
| Q8 | Группировка секций | Плоский список (без group headers) |
| Q9 | Loading state ID | `CircularProgressIndicator` в позиции ID |
| — | Раскрытие ID | Text wrap (monospace) в одну колонку; toggle `Show` / `Hide` |
| — | QR sheet | QR на светлом фоне (сканируем в обеих темах), без raw-ID текстом, drag-handle, wrap-height |
| — | Inline-name-edit | Save по Enter/Done/blur при валидном; invalid/taken — остаётся в edit; пустое → не меняет имя |
| — | Logout-loading | Спиннер в кнопке диалога; диалог модален до перехода в 1.1 |

## Десктоп-раскладка (этап M3, сверено с корпусом)

> Добавлено при реализации M3. Сведено с `nox-desktop-screens/screens/02-settings.md`.

- Десктоп (`>= 840dp`) — **list-detail**: `NavigationRail` (шелл) + settings-menu-pane ≈340 (`Account` + разделы 7.2–7.7 + `Log out`) + detail-pane (контент ≤680). Выбор пункта подсвечивает его (`secondaryContainer`) и меняет detail-pane **без** push (контейнер `AppListDetailWidget`); по умолчанию выбран `Account` (карта идентичности). Контент подэкранов 7.2–7.7 в detail-pane — переиспользуемые `…Body`-виджеты (без собственного AppBar).
- **Раскрытие ID на десктопе отсутствует** (`Show/Hide` нет): ID всегда замаскирован, вместо reveal — inline account-QR в карте идентичности + `Copy` + `Show QR` (центрированный `Dialog`). Обоснование — Принцип I (минимизация раскрытия секрета). Мобайл сохраняет `Show/Hide` (верхняя часть спеки).
- **Logout-таргет — 1.1 Splash** (как в основной части спеки). Десктоп-корпус `02-settings` и мобайл-корпус `7-1-settings` ошибочно ведут на Login — это дрейф корпусов; канон — Splash (Принцип II).
