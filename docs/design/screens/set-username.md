# 2.3 Установка имени пользователя

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 2.3 закрыты 2026-05-29.

## Назначение

Экран **опционального** изменения публичного имени (label). Показывается только при первом успешном входе под новым идентификатором.

Сервер **уже назначил** имя `User<random>` (например `User1234`) **в момент логина** — поэтому имя у пользователя есть всегда, состояния «без имени» не существует (закрывает edge с убийством приложения на этом экране). 2.3 лишь предлагает **изменить** это имя; шаг можно пропустить — тогда остаётся `User<random>`.

Имя — глобально уникальное **с учётом регистра** (Anna ≠ anna), лимит 32 символа, charset — **латиница + цифры + `-`, `_`, `.`** (см. [overview.md](../overview.md#идентичность-пользователя)).

## Контекст и переходы

- **Откуда:**
  - 2.1 Вход по идентификатору — после первого успешного submit под новым идентификатором.
  - 2.2 Сканирование QR — то же через 2.1 auto-submit.
- **Куда:**
  - **4.1 Tab bar shell** — после сохранения нового имени или пропуска (остаётся `User<random>`).
  - **3.1 Универсальный экран ошибки** — для fatal-сценариев при сохранении имени.

**Системный back** трактуется как «пропустить»: имя остаётся текущим (`User<random>`), переход в 4.1. Доступна также явная кнопка `Skip`.

## Лейаут

Material Scaffold с `resizeToAvoidBottomInset: true`; фон — `ColorScheme.surface`. Сверху вниз:

1. **AppBar (M3):** с wordmark `NOX` (onboarding-экран, как 2.1); адаптируется под тему.
2. **Центр:** однострочный `TextField`, **предзаполненный текущим именем** (`User<random>`), лимит 32, встроенный counter, постоянный helperText.
3. **Низ:** primary `FilledButton` `Done` + secondary `TextButton` `Skip`.

При фокусе поля клавиатура поднимается; контент сжимается под видимую область.

## Состояния

| Состояние | Описание |
|---|---|
| Prefilled | Поле предзаполнено текущим `User<random>` (валидно и уникально). `Done` enabled. |
| Checking-availability | Имя изменено, локально OK, идёт серверная проверка занятости (debounced ~300 мс). Suffix-индикатор в поле. |
| Filled-invalid (charset) | Введён недопустимый символ. errorText `Contains invalid characters (allowed: letters, digits, - _ .)`. `Done` disabled. |
| Filled-invalid (taken) | Имя занято. errorText `This name is taken`. `Done` disabled. |
| Empty | Поле очищено. `Done` disabled (имя не может быть пустым — у пользователя всегда есть label). Можно `Skip`. Placeholder `How others will see you` виден только в этом состоянии (по умолчанию поле предзаполнено текущим именем). |
| Filled-valid | Длина OK, charset OK, имя свободно. `Done` enabled. |
| Loading-submit | Идёт сохранение нового имени. Поле и кнопки disabled; индикатор внутри primary button. |
| Race-taken | На submit пришёл ответ «занято» (race между real-time и submit). Inline-error, фокус возвращается в поле. |
| Fatal | Server-fatal → передача в 3.1. |

## Взаимодействия

- Тап в поле → клавиатура поднимается.
- Ввод символов → локальная валидация charset → при успехе debounced проверка занятости (~300 мс).
- **`Done`** или **Enter / Done** на клавиатуре → сохранение текущего значения поля (должно быть валидным, уникальным, непустым).
- **`Skip`** или **системный back / жест back** → пропуск: имя остаётся `User<random>`, переход в 4.1.

## Material-компоненты

- `Scaffold` с `resizeToAvoidBottomInset: true`.
- `AppBar` (M3) с wordmark `NOX`; адаптируется под тему через `ColorScheme`.
- `TextField` (M3 outlined) с `maxLength: 32`, встроенным counter, постоянным `helperText`, suffix-`CircularProgressIndicator` в Checking-availability.
- `FilledButton` — primary `Done`.
- `TextButton` — secondary `Skip`.
- `CircularProgressIndicator` (внутри primary button) — Loading-submit.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar wordmark | `NOX` |
| Field label | `Name` |
| Placeholder | `How others will see you` |
| HelperText (постоянный) | `Others see this name. You can change it now or later in Settings.` |
| Counter | автоматический `N/32` |
| Error: charset | `Contains invalid characters (allowed: letters, digits, - _ .)` |
| Error: taken | `This name is taken` |
| Loading-submit | — (no text, only indicator) |
| Primary action | `Done` |
| Secondary action | `Skip` |

## Принятые решения (Q1–Q11)

| # | Вопрос | Решение |
|---|---|---|
| Q1 / Q11 | Обязательность и поведение back | Опционально. Имя `User<random>` назначено при логине; 2.3 даёт его изменить. `Skip` / back → остаётся `User<random>` → 4.1. |
| Q2 | Минимальная длина | Без минимума; но сохранить можно только непустое валидное имя (пустое поле → только Skip) |
| Q3 | Charset | Латиница + цифры + `-`, `_`, `.` |
| Q4 | Регистр-уникальность | Регистр учитывается (Anna ≠ anna) |
| Q5 | Резервированные имена | Не запрещаем ничего; только charset и уникальность |
| Q6 | Хедер экрана | AppBar M3 с wordmark `NOX` |
| Q7 | Helper text | Постоянно отображается |
| Q8 | Enter / Done на клавиатуре | Эквивалент тапу `Done` |
| Q9 | Race на submit | Inline-error, фокус возвращается в поле |
| Q10 | Формат default | `User<random>` (например `User1234`), назначается при логине |
| — | LOGIC-3 (kill на 2.3) | Имя назначено уже при логине → splash всегда ведёт в 4.1, состояния «без имени» нет |
