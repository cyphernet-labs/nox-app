<!--
  PREVIEW TEMPLATE — the SHORT team brief (summary of the sibling <slug>-solution.md).
  Fill every section; delete guidance comments and any section that is genuinely N/A (say why in one line).
  Whole brief must be readable in ~5 minutes: tables and diagrams over prose.

  PHASE RULE: no file-by-file change map, no code, no migration/test plans — this describes the SOLUTION.
  NO document-level status apparatus: no status badge, readiness, risk rating, estimate, «Границы» line, mode
  field or «Что это» meta preamble. This reads as documentation of how the thing works. What is unresolved goes
  in Open Questions; what is not covered goes in Out of Scope.
  Markers 🟢 🟡 🔴 ⚠️ are used INSIDE the content, where they carry meaning (exists / partial / missing,
  decided / open, resolved / unresolved).
  Diagrams are REQUIRED: at least one component view + one flow/sequence view. Keep each to ~10 nodes.
  Russian prose; identifiers, paths, formats and command names verbatim in English.
-->
# <Тема>

---

## 1. Суть

<3–5 предложений: что решаем → как решаем в одном абзаце → главное ограничение. Без деталей, они ниже.>

---

## 2. Из чего состоит

Легенда: 🟢 есть в проекте · 🟡 частично · 🔴 ещё нет

| Часть | За что отвечает | |
|---|---|:--:|
| `<имя>` | <…> | 🔴 |

```mermaid
flowchart LR
  A["<часть>"] -->|"<что ходит>"| B["<часть>"]
```

<⚠️ Отдельной строкой назови связи, которых НЕТ намеренно — читатель домысливает лишние стрелки.>

---

## 3. Как это работает

<Основной путь от начала до конца. Одна диаграмма — sequence, если важен порядок во времени, flowchart, если
важна логика ветвления.>

```mermaid
sequenceDiagram
  participant A as <часть>
  participant B as <часть>
  A->>B: <что>
  B-->>A: <что>
```

---

## 4. Форматы

<Только то, что реально зафиксировано: структура ссылки, поля payload с размерами, имена команд/событий.
Таблицей. Если формат не решён — строка с 🟡 и ссылкой на вопрос.>

| Поле | Что | Размер |
|---|---|---|

---

## 5. Решения

| Решение | Выбор | Почему | Пересмотреть, если |
|---|---|---|---|
| <…> | <…> | <…> | <…> |

---

## 6. Пограничные случаи

<Таблицей: ситуация → что происходит. Только те, что меняют дизайн, а не все мыслимые.>

| Случай | Что происходит |
|---|---|

---

## 7. Открытые вопросы и блокеры

<ОБЯЗАТЕЛЬНАЯ секция. 🔴 блокер · 🟡 вопрос · 🟢 принятое допущение. Ссылайся на реестр по id, где он есть.>

| | Вопрос / блокер | На ком | Реестр |
|---|---|---|---|
| 🔴 | <…> | <…> | <Q#> |

---

## 8. Вне скоупа

<Что не покрыто и где живёт вместо этого.>
