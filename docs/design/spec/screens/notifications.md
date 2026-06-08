# 7.2 Уведомления

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 7.2 закрыты 2026-05-29.

## Назначение

Подраздел настроек 7.1. **Один переключатель push-уведомлений** — on / off. Никаких дополнительных параметров (preview, sound, vibration, quiet hours) на этом этапе **не предусмотрено**.

Push приходят **только по «своим» чатам** — созданным с этого устройства либо тем, в которых пользователь писал / которые открывал (см. [overview.md / Настройки](../overview.md#настройки)). Глобального флуда по всем чатам нет; переключатель управляет push для этого набора.

## Контекст и переходы

- **Откуда:** 7.1 — тап на `Notifications`.
- **Куда:**
  - Back-стрелка → 7.1.
  - Системные настройки приложения (при отказе в push на уровне ОС — кнопка `Open settings` в баннере).

## Лейаут

Material Scaffold; адаптируется под тему. Сверху вниз:

- **AppBar (M3):** title `Notifications`, back-стрелка.
- **Body:**
  - При permission-denied (системный отказ ОС) — `MaterialBanner` наверху с пояснением и кнопкой `Open settings`.
  - **Единственный `SwitchListTile`** `Enable notifications` (on / off).

## Состояния

| Состояние | Описание |
|---|---|
| Loaded (permission OK) | Виден `SwitchListTile`; пользователь управляет переключателем. |
| Loaded (permission denied) | Banner поверх; switch остаётся, но эффект ограничен системной настройкой. |
| Permission-prompt | Системный диалог разрешения push (управляется ОС). |
| Inline-error | Не удалось сохранить — snackbar. |

## Взаимодействия

- **Тап на toggle** → переключение и сохранение.
- **Тап на `Open settings`** в баннере → системные настройки приложения (intent / deeplink).
- **Тап на back** → 7.1.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с back-стрелкой и title.
- `MaterialBanner` (M3) — permission-denied состояние.
- `SwitchListTile` (M3) — единственный переключатель.
- `SnackBar` (M3) — обратная связь.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `Notifications` |
| AppBar back tooltip | `Back` |
| Switch label | `Enable notifications` |
| Permission banner title | `Notifications are blocked` |
| Permission banner message | `Allow notifications in system settings to receive messages from your chats.` |
| Permission banner action | `Open settings` |
| Inline-error snackbar | `Could not save. Try again.` |

## Принятые решения (Q1–Q4)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Master toggle | Есть, и это **единственный** контрол на экране |
| Q2 | Дополнительные параметры | Нет — только push on/off (preview / sound / vibration / quiet hours **исключены**) |
| Q3 | Permission-denied | `MaterialBanner` сверху списка с кнопкой `Open settings` |
| Q4 | Scope уведомлений | Только «свои» чаты (созданные / писал / открывал) |
