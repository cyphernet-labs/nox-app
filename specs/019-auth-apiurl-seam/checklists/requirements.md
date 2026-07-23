# Specification Quality Checklist: Auth token + apiUrl seam (S5)

**Created**: 2026-07-26 · **Feature**: [spec.md](../spec.md)

## Content Quality
- [x] No implementation details leak beyond the existing seam vocabulary (ApiClient/AppConfig name the code this extends)
- [x] Focused on developer/integration value (backend-ready seam), zero user-facing change
- [x] All mandatory sections completed

## Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain (3 clarifications resolved with recommended answers)
- [x] Requirements testable and unambiguous
- [x] Success criteria measurable
- [x] Acceptance scenarios defined; edge cases identified
- [x] Scope clearly bounded (Out of Scope explicit); dependencies/assumptions identified

## Feature Readiness
- [x] All FRs have acceptance criteria
- [x] Inert-without-apiUrl + 401→existing-forced-logout keep it behavior-neutral for the UI

## Notes
- Internal transport-seam feature: the value is a backend-ready auth/apiUrl seam with real client
  behavior (attach-token, 401→logout) but inert values (apiUrl null, token null) until the backend
  is chosen. apiUrl/token/header shapes are example/TBD per blueprints 14/15/16.
