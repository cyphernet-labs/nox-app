# Specification Quality Checklist: Сервер в сети Tor — onion-адрес только для своих устройств

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-03
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

**Оговорка о технических деталях — та же, что у фазы 036.** Предмет фазы — сама сеть Tor и её механизмы: onion-сервис, авторизация клиентов, вердикт сети о версии. Требование «доступ к onion только по ключам доступа» без названия механизма превращается в «доступ только своим», а это уже правда про приветствие с подписью фазы 032 и не говорит, от чего защищает этот слой: от сканирования, заваливания соединениями и слежки за доступностью — до того, как соединение дойдёт до сервера. То же с минимальной версией tor 0.4.9: это наблюдаемый факт сети, а не выбор реализации. Упоминания `client_backend/CLAUDE.md` и конституции — граница ответственности: правила проекта называют один процесс, и фаза обязана их поправить.

Где деталь была бы лишней, спека её не называет: имена команд, полей и события, раскладка ссылки нового формата, способ управления tor, форма хранения ключей, перечисление сетевых интерфейсов и интервалы опроса — всё это уходит в правку контракта, `plan.md` и `research.md`.

**Проверка совместимости вынесена в критерий успеха (SC-011).** Этап меняет провод только добавлениями, и его соответствие Принципу VII держится на том, что нынешний клиент новое пропускает. Это утверждение проверяется, а не принимается на веру.

**Валидация**: одна итерация, все пункты проходят. Маркеров `[NEEDS CLARIFICATION]` нет: решения владельца от 2026-10-03 закрывают объём, остальное вынесено в допущения. Открытые места, которые стоит пройти на `/speckit-clarify`: флаг выключения Tor, показ на странице статуса числа устройств с доступом, допустимость короткого обрыва onion-соединений при перепубликации.
