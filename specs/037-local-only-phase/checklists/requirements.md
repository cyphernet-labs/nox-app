# Specification Quality Checklist: Локальный продукт — один человек на своём сервере

**Purpose**: Проверить полноту и качество спецификации перед планированием
**Created**: 2026-09-10
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

**Об «отсутствии деталей реализации».** Требования (FR-001…FR-022) сформулированы поведенчески: что система делает и чего не делает, а не какие файлы удаляются. Имена артефактов (`001_init.sql`, `pair_tokens`, `session.is_owner`) встречаются только в разделах Edge Cases и Assumptions — там, где без них невозможно описать краевой случай («база разработчика несовместима и должна быть удалена»). Это соответствует дому style фаз 033–035 и не переносит проектные решения в спеку.

**Об измеримости SC-003.** Критерий «число тестов уменьшается только за счёт удалённых» проверяется сравнением до/после: список удалённых тест-файлов известен заранее и фиксируется в плане. Ни один оставшийся тест не должен упасть — это бинарная проверка локального гейта.

**Особенность фазы: она преимущественно вычитающая.** Три из четырёх пользовательских историй описывают исчезновение возможностей, и это осознанно. Единственное добавление — выключенный шов приглашения (User Story 3), и именно он несёт всю новую вёрстку и голдены.

**Риск, вынесенный в план, а не в спеку.** Удаление кода, переплетённого с живым (ветка ожидания внутри общего рукопожатия, признак владения сквозь слой сессии), — главный источник регрессий. План обязан разложить это на шаги, каждый из которых заканчивается зелёным гейтом, а не одним большим удалением.
