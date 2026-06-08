# 5.3 Просмотр файла

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 5.3 закрыты 2026-05-29.

## Назначение

Экран информации о файле-вложении и его скачивания. **Preview содержимого файла не показывается** — только иконка типа, имя и размер. Поддерживает auto-скачивание в кэш и явное сохранение в Downloads.

## Контекст и переходы

- **Откуда:** 5.2 Лента чата — тап на файл-вложение в сообщении.
- **Куда:**
  - Back / back-стрелка → возврат в 5.2.
  - **3.1 Универсальный экран ошибки** — fatal-сценарии (файл удалён сервером, общая сетевая fatal).

## Лейаут

Material Scaffold; адаптируется под тему. Сверху вниз:

1. **AppBar (M3):** сплошной, цвет — `ColorScheme.surface` (адаптируется под тему). Слева — back-стрелка; title — имя файла (ellipsis при переполнении); справа — иконка `Save`.
2. **Body:** центрированная column:
   - крупная иконка типа файла по **единому маппингу** из [overview.md / Файлы](../overview.md#файлы-иконки-типов-без-превью);
   - filename (по центру, перенос если длинный);
   - размер файла (например `2.4 MB`).
3. **Loading-индикатор:** во время auto-download — горизонтальный `LinearProgressIndicator` с определённым % (под AppBar или под filename).

## Состояния

| Состояние | Описание |
|---|---|
| Loading | Auto-скачивание в кэш. Linear progress bar (определённый %). `Save` в AppBar disabled. |
| Loaded | Файл закэширован. `Save` enabled. Progress bar скрыт. |
| Inline-error | Не удалось скачать (сеть). `SnackBar` (transient) с action retry (см. [overview.md / Уровни ошибок](../overview.md#уровни-ошибок-и-обратной-связи)). |
| Fatal | Передача в 3.1 (embedded). |

При открытии экрана: если файл уже в кэше — сразу состояние Loaded; иначе Loading → Loaded.

## Взаимодействия

- **Открытие экрана** → если файл не в кэше, запускается auto-скачивание; прогресс отображается линейным баром с %.
- **Тап на `Save` в AppBar** → копирование закэшированного файла в системную папку Downloads + snackbar `Saved to Downloads`.
- **Тап на back** → возврат в 5.2.
- **Long-press на icon / filename** — no-op на этом этапе.
- **Share** — отсутствует на этом этапе.
- **Open in external app** — отсутствует на этом этапе.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) — сплошной (`ColorScheme.surface`); адаптируется под тему.
- `IconButton` — `Save` в actions AppBar.
- `Icon` (Material Icons) — крупная иконка типа файла в body.
- `Text` — filename и размер.
- `LinearProgressIndicator` — Loading.
- `SnackBar` (M3) — confirmation после Save, inline-error.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar back tooltip | `Back` |
| AppBar title | filename (динамически) |
| Save tooltip | `Save` |
| Snackbar после Save | `Saved to Downloads` |
| Inline-error (network) | `Could not download file. Check your connection and try again.` |

## Принятые решения (Q1–Q9)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Supported types preview | Никакие; только иконки типов |
| Q2 | AppBar стиль | Сплошной, адаптируется под тему (M3 `ColorScheme.surface`) |
| Q3 | Download UX | Мгновенное сохранение в Downloads + snackbar |
| Q4 | Share UX | Нет share |
| Q5 | Содержимое body | Иконка + filename + размер |
| Q6 | Open в external app | Нет |
| Q7 | Когда скачиваем | Auto при открытии 5.3 (или из кэша, если уже есть) |
| Q8 | Long-press | Ничего |
| Q9 | Loading UI | Linear progress bar с % |
