# 6.1 Создание чата

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 6.1 закрыты 2026-05-29.

## Назначение

Полноэкранная форма создания нового чата. Открывается по тапу центральной `+` в нижней панели 4.1. Имя чата вводится с **real-time валидацией уникальности** (см. [overview.md](../overview.md#создание-чата)); лимит — 64 символа, **charset не ограничен**. Доступно любому пользователю. **Описания у чата нет** — формой управляется только имя.

## Контекст и переходы

- **Откуда:** 4.1 Tab bar shell — тап на центральной `+` из любого таба.
- **Куда:**
  - **5.2 Лента чата (нового)** — сразу после успешного создания.
  - Back / cancel → возврат на исходный таб (без подтверждения, даже если поле заполнено).
  - **3.1 Универсальный экран ошибки** — для fatal-сценариев (server 5xx и подобное).

## Лейаут

Material **полноэкранный** Scaffold; адаптируется под тему. Сверху вниз:

1. **AppBar (M3):** back-стрелка слева; **title — `New chat`** (текстовый, описывает задачу; wordmark не используется — это pushed-экран, паттерн title как у 5.2/5.4/7.x).
2. **Body:** column:
   - поле имени чата (`TextField` с лимитом 64 + counter + `helperText` / `errorText`).
3. **Низ:** primary `FilledButton` `Create` на всю ширину.

## Состояния

| Состояние | Описание |
|---|---|
| Empty | Поле пустое. `Create` disabled. |
| Checking-availability | Локально OK, идёт серверная проверка уникальности (debounced ~300 мс). Suffix-индикатор в поле. |
| Filled-invalid (taken) | Имя занято (по real-time проверке). errorText `This name is taken`. `Create` disabled. |
| Filled-valid | Длина OK, имя свободно. `Create` enabled. |
| Loading-submit | Идёт создание на сервере. Поле и кнопка disabled; `CircularProgressIndicator` внутри primary button. |
| Inline-error (network) | Не удалось отправить (сеть). errorText под полем или banner. `Create` снова enabled для retry. |
| Fatal | Server-fatal → передача в 3.1 (embedded). |

Состояния «Filled-invalid (charset)» нет — charset не ограничен.

## Взаимодействия

- Тап в поле → системная клавиатура поднимается.
- Ввод символов → debounced проверка уникальности на сервере (без локальной charset-валидации).
- **`Create`** или **Enter / Done** → отправка имени.
- **Back / cancel** → возврат на исходный таб без подтверждения; введённый текст теряется, даже если поле было заполнено.
- **Long-press на поле** — стандартное системное (paste / select).

## Material-компоненты

- `Scaffold` (полноэкранный).
- `AppBar` (M3) с title `New chat` и back-стрелкой; адаптируется под тему.
- `TextField` (M3 outlined) с `maxLength: 64`, встроенным counter, `helperText` / `errorText`, suffix-`CircularProgressIndicator` в Checking-availability.
- `FilledButton` — primary action `Create`.
- `CircularProgressIndicator` (внутри primary button) — Loading-submit.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `New chat` |
| AppBar back tooltip | `Back` |
| Field label | `Chat name` |
| Placeholder | `e.g. Random thoughts` |
| Counter | автоматический `N/64` |
| Error: taken | `This name is taken` |
| Inline-error (network) | `Could not create chat. Check your connection and try again.` |
| Loading-submit | — (только индикатор) |
| Primary action | `Create` |

## Принятые решения (Q1–Q9)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Поле описания | Без описания (только имя) |
| Q2 | Charset имени | Любые символы (без ограничений) |
| Q3 | AppBar | Title `New chat` + back (исправлено в ревью: pushed-экраны именуют задачу, не wordmark) |
| Q4 | Layout формы | Полный экран |
| Q5 | После успешного создания | Сразу в 5.2 нового чата |
| Q6 | Cancel при заполненной форме | Без подтверждения |
| Q7 | Auto-suggested name | Placeholder-подсказка `e.g. Random thoughts` |
| Q8 | Server-ошибки | Inline для сети; fatal → 3.1 |
| Q9 | Loading-submit UI | Индикатор внутри primary button |
