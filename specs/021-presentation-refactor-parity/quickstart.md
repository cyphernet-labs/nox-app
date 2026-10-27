# Quickstart: валидация рефакторинга

**Phase 1.** Как доказать, что каждая задача (a) не сломала UI/логику и (b) для паритета — закрыла gap.

## Предпосылки

- FVM Flutter 3.44.1; из корня пакета `nox_app`.
- Голдены рендерятся/верифицируются локально на Apple Silicon/macOS (project-rule).

## Базовый гейт (для КАЖДОЙ задачи перед merge)

```bash
make gate            # generate → format → analyze → test (голдены исключены)
make golden-verify   # обе категории: page-mobile (360) + page-desktop (1280×800)
```

Оба зелёные — обязательное условие merge `--no-ff` в `develop` (без push).

## Валидация behavior-preserving задачи (E-вынос / O-оптимизация)

1. До изменения: `make golden-verify` зелёный (baseline).
2. Сделать вынос/оптимизацию.
3. `make golden-verify` снова — **ожидается 0 churn**. Любой diff = непреднамеренное изменение → разобрать
   (НЕ перегенерировать вслепую).
4. `make gate` зелёный. Если задача добавила общий виджет — grep подтверждает 0 остаточных копий (SC-003).

## Валидация паритет-фикса (P: R1–R6) — fail-first

1. Написать тест/golden на «отстающей» ветке, который ПАДАЕТ на текущем коде (доказывает gap). Примеры:
   - R1: `expect(find.byType(PopScope), findsOneWidget)` в desktop blocking-дереве error_page (сейчас нет → падает).
   - R3: desktop-golden на Settings-табе — subtitle ≠ 'Chats' (сейчас 'Chats' → падает).
   - R4: a11y-тест на rail — `SemanticsFlag.isButton` + `isSelected` (сейчас нет → падает).
   - R5: widget-тест — при `isSubmitting` mobile leading disabled / pop подавлен (сейчас нет → падает).
2. Реализовать фикс.
3. Тест зелёный; осознанно перегенерировать baseline «отстающей» ветки (`make golden-update FILE=…`) — только
   там, где паритет ПРАВОМЕРНО изменил layout; глазами подтвердить корректность нового baseline.
4. `make gate` + `make golden-verify` зелёные.

## Быстрая проверка паритета экрана (SC-005)

Прогнать соответствующий page-mobile и page-desktop golden рядом и сверить набор действий/состояний против
`contracts/parity-matrix.md`. Строка контракта закрыта ⇔ обе ветки несут одинаковый набор (или различие
отмечено ✔ confirmed-intentional).

## Ссылки

- Задачи: `docs/presentation-refactor-review.md` (R1–R28) → `tasks.md` (после `/speckit-tasks`).
- Контракт паритета: `contracts/parity-matrix.md`. Компоненты/токены: `data-model.md`.
