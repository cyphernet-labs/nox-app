# Specification Quality Checklist: Экраны этапа M2 — Онбординг-формы

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-06-20
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

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
- Контекстная оговорка: проект ведёт UI-only фазу; ссылки на переиспользуемые продуктовые сущности из дизайн-корпуса/блюпринта (`OnboardCard`, `AppWindowTitlebarWidget`, семейство полей-ввода, дизайн-токены) — это доменный словарь, а не технологический выбор; допустимы (consistent с spec.md фичи 004). Аналогично, SC по тестовому покрытию (`widget`/`golden`/`make gate`) сохранены в стиле фичи 004 как проектная DoD-метрика.
- Валидация 2026-06-20 (после `/speckit-clarify` + состязательной верификации): 16/16 пунктов проходят. Исправления, внесённые в спеку: FR-003 (brand-fixed camera-overlay 2.2 по `design-system.md` §9.9), дропнутая QR-микрокопия (тултипы `Back`/`Flashlight`/`Switch camera`, permission-denied body), состав `OnboardCard` (logo + wordmark + hairline), per-screen `TitleBar`-заголовки, `Cancel`+scrim в десктоп-диалоге 6.1, case-sensitive уникальность 2.3, single-shot скан, непрозрачная permission-denied поверхность, выравнивание десктоп-лейаута QR (2.2) по `06-qr.md`.
