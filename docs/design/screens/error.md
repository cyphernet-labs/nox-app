# 3.1 Универсальный экран ошибки

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 3.1 закрыты 2026-05-29.

## Назначение

Универсальный параметризованный экран ошибки. Адаптируется под кейс через параметры (иконка, заголовок, сообщение, retry-callback). Два режима:

- **Embedded** — со стрелкой back, означающей, что 3.1 **не последний** экран в стеке. Системный back возвращает на предыдущий экран.
- **Blocking** — без AppBar; 3.1 — **последний** экран в стеке. Системный back свёртывает приложение.

Если конкретные параметры не переданы, показывается стандартный заголовок-заглушка («Something went wrong»).

## Контекст и переходы

Известные точки вызова:

| Источник | Режим | Сценарий |
|---|---|---|
| 1.1 Splash | Blocking | Ошибка чтения локального состояния (splash — последний в стеке). |
| 2.1 Вход | Embedded | Server-fatal на проверку идентификатора. |
| 2.2 QR-скан | Embedded | Системная недоступность камеры, server-fatal. |
| 2.3 Установка имени | Embedded | Server-fatal на отправку имени. |
| 5.1 / 5.2 / 5.3 / 5.4 | Embedded | Server-fatal загрузки/операции в чатах (generic Server-fatal). |
| 6.1 Создание чата | Embedded | Server-fatal при создании чата (generic Server-fatal). |
| 7.1 / 7.x | Embedded | Server-fatal операции настроек (generic Server-fatal). |

Переходы:

- **Retry-action** → `onRetry` (определяется вызывающей стороной).
- **Back-стрелка** (только embedded) → `onBack` или дефолтный `Navigator.pop`.
- **Системный back** (embedded) → эквивалент back-стрелке.
- **Системный back** (blocking) → свёртывание приложения.

## Лейаут

Material Scaffold; цвета адаптируются под тему через `ColorScheme`. Сверху вниз:

- **Embedded:**
  1. `AppBar` (M3) с back-стрелкой; адаптируется под тему.
  2. Центр (column): иконка → заголовок → сообщение.
  3. Низ: primary `FilledButton` с retry-текстом.
- **Blocking:**
  1. Без `AppBar` — full-screen.
  2. Центр (column): иконка → заголовок → сообщение.
  3. Низ: primary `FilledButton` с retry-текстом.

Иконка — **увеличенная, 48–96dp**. Источник — **Material Icons** (по умолчанию `Icons.error_outline`, если param не передан).

## Состояния

| Состояние | Описание |
|---|---|
| Embedded | Со стрелкой back; retry-action доступен. |
| Blocking | Без AppBar; пользователь может тапнуть retry или свернуть приложение системным back. |
| Loading-retry | После тапа retry — кнопка disabled, внутри `CircularProgressIndicator`. Пока вызывающая сторона не переключит экран. |

Появление экрана — **без анимации** (мгновенный показ).

## Взаимодействия

- **Retry-action** → вызов `onRetry`; кнопка переходит в Loading-retry.
- **Back-стрелка** (embedded) → `onBack` или дефолтный `Navigator.pop`.
- **Системный back** (embedded) → эквивалент back-стрелке.
- **Системный back** (blocking) → свёртывание приложения.
- **При retry → новая ошибка**: содержимое текущего 3.1 **обновляется** новыми параметрами; стек не растёт (нет 3.1 поверх 3.1).

## Параметры экрана

| Параметр | Тип | Описание |
|---|---|---|
| `mode` | enum | `blocking` или `embedded` |
| `icon` | image (опц.) | иконка ошибки; если не передана — default Material «error»-иконка |
| `title` | string (опц.) | заголовок; если не передан — `Something went wrong` |
| `message` | string (опц.) | подробное сообщение; если не передан — `Please try again.` |
| `onRetry` | callback | действие при тапе retry |
| `onBack` | callback (опц., embedded) | действие при back; по умолчанию `Navigator.pop` |

Текст retry-action не передаётся параметром — **локализуется** (English / Українська / системный с fallback на English; см. правило локализации в [overview.md](../overview.md)).

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3, только embedded) — с back-стрелкой; адаптируется под тему.
- `Icon` — увеличенная, 48–96dp, из Material Icons (default — `Icons.error_outline`).
- `Text` — заголовок и сообщение.
- `FilledButton` — retry-action.
- `CircularProgressIndicator` (внутри primary button) — Loading-retry.

## Микрокопирайт

UI-тексты — на английском (см. [overview.md / Терминология и брендинг](../overview.md#терминология-и-брендинг)). Кнопка retry-action **локализуется** во время сборки; в спецификации фиксируется English.

| Элемент | Текст (EN) |
|---|---|
| Retry-action button | `Try again` |
| Default title | `Something went wrong` |
| Default message | `Please try again.` |
| AppBar back tooltip (embedded) | `Back` |
| AppBar title (embedded) | `(empty)` |

Заготовки текстов для типовых сценариев (могут быть переопределены параметрами):

| Сценарий | Title | Message |
|---|---|---|
| No network | `No connection` | `Check your connection and try again.` |
| Server-fatal | `Something went wrong` | `Please try again in a few minutes.` |
| Camera unavailable (2.2) | `Camera unavailable` | `Could not access the camera. Try restarting the app.` |
| Local state corrupt (1.1) | `Could not start NOX` | `Local data is corrupted. Try reinstalling the app.` |

## Принятые решения (Q1–Q9)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Системный back и режимы | Embedded со стрелкой back = не последний в стеке (back возвращает на предыдущий экран). Blocking без AppBar = последний в стеке (back свёртывает приложение). |
| Q2 | Текст retry-action | Локализуется (English / Українська / системный с fallback на English); в спеках фиксируем `Try again` |
| Q3 | Loading-retry | Индикатор внутри кнопки (disabled + spinner) |
| Q4 | Default-иконка | Есть default (общая Material «error»-иконка) |
| Q5 | Размер иконки | Увеличенная, 48–96dp |
| Q6 | Источник иконок | Material Icons |
| Q7 | AppBar в blocking | Без AppBar |
| Q8 | Анимация появления | Без анимации |
| Q9 | Stacking при retry-fail | Замена содержимого текущего 3.1 (стек не растёт) |
