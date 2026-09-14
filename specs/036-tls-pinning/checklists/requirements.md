# Specification Quality Checklist: TLS с пиннингом по отпечатку ключа сервера

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-09-07 · **переписан при переспецификации** 2026-09-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — *с оговоркой, см. Notes*
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders — *с оговоркой, см. Notes*
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details) — *с оговоркой, см. Notes*
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification — *с оговоркой, см. Notes*

## Notes

**Прежняя редакция этого чек-листа фиксировала как принятое решение «ключ TLS — тот же Ed25519-ключ личности».** Оно отменено 2026-09-14: спайк показал, что такой сертификат клиент не принимает. Чек-лист переписан вместе со спекой.

**Оговорка о «технических деталях», сознательная и повторяющаяся в четырёх пунктах.** Это фаза про транспорт, и её предмет — сами криптографические параметры. Требование «TLS 1.3, ECDSA P-256, отпечаток `sha256(SPKI)`» нельзя переформулировать без технологии, не потеряв его смысл: «соединение должно быть защищено» не проверяемо и уже было бы правдой про любое шифрование без аутентификации, то есть ровно про то, от чего эта фаза защищает. То же касается упоминаний Android-манифеста (`usesCleartextTraffic` — наблюдаемый факт репозитория, а не деталь реализации) и `server_identity` (место, где живёт ключ, — это граница ответственности, а не выбор технологии).

Где деталь всё-таки была бы лишней, спека её не называет: как именно клиент вызывает проверку, в каком файле живёт чистая функция, каким пакетом считается хеш, как устроен `HttpClient` — всё это ушло в [plan.md](../plan.md) и [research.md](../research.md).

**Что осталось за спекой сознательно**: точная микрокопия двух новых строк интерфейса (решается при правке дизайн-спецификации, FR-025) и вопрос Q14 (ATS и App Review), который придётся закрыть до релиза, но не этой фазой.
