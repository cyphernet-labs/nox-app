# 7.4 Язык

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 7.4 закрыты 2026-05-29.

## Назначение

Подраздел настроек 7.1. Выбор языка UI: **System / English / Українська**. Правила fallback при несоответствии системного языка — см. [overview.md / Настройки](../overview.md#настройки): если системный язык не EN/UK — используется English.

## Контекст и переходы

- **Откуда:** 7.1 — тап на `Language`.
- **Куда:** Back-стрелка → 7.1.

## Лейаут

Material Scaffold; адаптируется под тему. Сверху вниз:

- **AppBar (M3):** title `Language`, back-стрелка.
- **Body:** `ListView` с тремя `RadioListTile` (паттерн как в 7.3):
  - `System` (по умолчанию);
  - `English`;
  - `Українська`.

## Состояния

| Состояние | Описание |
|---|---|
| Loaded | Опции отображаются; текущая selected. |
| Inline-error | Не удалось сохранить — snackbar. |

## Взаимодействия

- **Тап на `RadioListTile`** → переключение языка **immediately** (live re-render всех строк) + сохранение.
- При выбранной опции **`System`** — приложение **следит за изменением системного locale на лету** и применяет новый язык немедленно.
- **Тап на back** → 7.1.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с back-стрелкой и title.
- `RadioListTile` (M3) — три опции.
- `SnackBar` (M3) — обратная связь.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `Language` |
| AppBar back tooltip | `Back` |
| Option: System | `System` |
| Option: English | `English` |
| Option: Українська | `Українська` |
| Inline-error snackbar | `Could not save. Try again.` |

## Принятые решения (Q1–Q3)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Apply timing | Immediately (live re-render) |
| Q2 | Подпись `System` | Просто `System` (без подсказки про эффективный язык) |
| Q3 | Смена OS-локали во время работы | Авто-применить немедленно |
