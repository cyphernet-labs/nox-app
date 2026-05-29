# 7.3 Внешний вид

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 7.3 закрыты 2026-05-29.

## Назначение

Подраздел настроек 7.1. Управляет темой приложения: **System / Light / Dark**. Адаптация всех компонентов под выбранную тему — через M3 `ColorScheme` (см. [overview.md / Дизайн-фреймворк](../overview.md#дизайн-фреймворк)).

Других параметров внешнего вида (accent color, font size, и т. п.) на этом этапе не предусмотрено.

## Контекст и переходы

- **Откуда:** 7.1 — тап на `Appearance`.
- **Куда:** Back-стрелка → 7.1.

## Лейаут

Material Scaffold; адаптируется под текущую тему (обновляется immediately при выборе). Сверху вниз:

- **AppBar (M3):** title `Appearance`, back-стрелка.
- **Body:** `ListView` с тремя `RadioListTile`:
  - `System` (по умолчанию);
  - `Light`;
  - `Dark`.

## Состояния

| Состояние | Описание |
|---|---|
| Loaded | Опции отображаются; текущая selected. |
| Inline-error | Не удалось сохранить — snackbar. |

## Взаимодействия

- **Тап на `RadioListTile`** → переключение темы **immediately (live preview)** + сохранение.
- **Тап на back** → 7.1.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с back-стрелкой и title.
- `RadioListTile` (M3) — три опции.
- `SnackBar` (M3) — обратная связь.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `Appearance` |
| AppBar back tooltip | `Back` |
| Option: System | `System` |
| Option: Light | `Light` |
| Option: Dark | `Dark` |
| Inline-error snackbar | `Could not save. Try again.` |

## Принятые решения (Q1–Q3)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | UI выбора темы | 3 `RadioListTile` |
| Q2 | Дополнительные параметры | Только тема (без accent / font size) |
| Q3 | Apply behavior | Immediately (live preview) |
