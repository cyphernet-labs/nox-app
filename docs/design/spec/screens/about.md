# 7.7 О приложении

> Детальная спецификация экрана. Часть [карты экранов](../top-level-screens.md). Общие решения — в [overview.md](../overview.md). Все верхнеуровневые открытые вопросы по 7.7 закрыты 2026-05-29.

## Назначение

Подраздел настроек 7.1. Показывает **только** версию и build-номер приложения. Никаких других пунктов (year/copyright, website URL, open-source licenses, credits) на этом этапе не выводится.

## Контекст и переходы

- **Откуда:** 7.1 — тап на `About`.
- **Куда:** Back-стрелка → 7.1.

## Лейаут

Material Scaffold; адаптируется под тему. Сверху вниз:

- **AppBar (M3):** title `About`, back-стрелка.
- **Body:** плоский `ListView` с **одним `ListTile`**:
  - title `Version`;
  - subtitle / trailing — динамическое значение `1.2.3 (build 456)` (из `package_info_plus`).

## Состояния

| Состояние | Описание |
|---|---|
| Loaded | Версия и build отображаются. |

## Взаимодействия

- **Тап на back** → 7.1.
- На `ListTile` версии — никакого действия по тапу.

## Material-компоненты

- `Scaffold`.
- `AppBar` (M3) с back-стрелкой и title.
- `ListTile` (M3) — единственный пункт.

## Микрокопирайт

| Элемент | Текст (EN) |
|---|---|
| AppBar title | `About` |
| AppBar back tooltip | `Back` |
| Version row label | `Version` |
| Version row value | `1.2.3 (build 456)` (динамически из package info) |

## Принятые решения (Q1–Q3)

| # | Вопрос | Решение |
|---|---|---|
| Q1 | Что показываем | Только Version + build number |
| Q2 | Open-source licenses | Не показываем (секции вообще нет) |
| Q3 | Layout | Плоский список (одна строка) |
