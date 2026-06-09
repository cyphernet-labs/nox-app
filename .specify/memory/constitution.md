<!--
Sync Impact Report
==================
Version change: 1.0.0 → 1.1.0
Bump rationale: MINOR — material expansion of the platform-scope constraint plus a broadening of
  Principle III's binding scope. Target platforms extended from iOS + Android (mobile only) to
  iOS, Android, Windows, Linux, macOS; web remains out of scope. No principle removed or
  redefined in a backward-incompatible way. Owner-approved, satisfying Principle II
  ("out-of-scope молча не расширяется").
Modified principles:
  III. Архитектурный блюпринт обязателен — binding scope broadened from "всего mobile-кода" /
       "mobile/Flutter-задача" to all client/Flutter code across the five target platforms; added
       an explicit clause that the blueprint's platform-specific native parts (build/secrets,
       push, deep-links, secure storage) are currently iOS/Android and MUST be extended to desktop
       — or a per-subsystem documented desktop-fallback fixed — before desktop work in that subsystem.
Modified sections:
  - Преамбула — "защищённый мобильный мессенджер (iOS + Android, Flutter)" →
    "защищённый кросс-платформенный мессенджер (iOS, Android, Windows, Linux, macOS; Flutter)".
  - Технологический контекст и ограничения — platform line expanded to the five-platform set
    (web out of scope); added a desktop-native-gap / documented-fallback note.
Added sections: none. Removed sections: none.
Templates reviewed:
  ✅ .specify/templates/plan-template.md — Constitution Check resolves dynamically against this file;
     platform-agnostic; no edit required.
  ✅ .specify/templates/spec-template.md — compatible; constitution mandates no new/removed section.
  ✅ .specify/templates/tasks-template.md — compatible; path-conventions are generic examples.
Runtime guidance / corpus corrected in this change-set (consistency, Principle II):
  ✅ CLAUDE.md — Project Overview platform line; blueprint task-scoping phrasing; Spec Kit
     constitution-version + Principle-III summary.
  ✅ docs/README.md — docs landing-page product framing.
  ✅ docs/patterns/mobile/README.md — blueprint purpose, status block (desktop gap), onboarding checklist.
  ✅ docs/patterns/mobile/01-stack-and-tooling.md — pubspec description string.
  ✅ docs/patterns/mobile/08-conventions-and-constitution.md — seeded lib/ CLAUDE.md skeleton.
  ✅ docs/patterns/mobile/06-theming.md — PlatformUtils desktop-getters prose framing.
  ✅ docs/patterns/mobile/17-analytics.md — "mobile-only"→"client-only"; platform super-property values.
  ✅ docs/patterns/mobile/09-build-and-secrets-infra.md — "Android+iOS only / no desktop jobs" claim.
  ✅ docs/vision.md — top-line product framing.
  ✅ docs/requirements.md — Целевые платформы list.
Deferred follow-ups (real desktop work — NOT one-line edits; tracked as feature-001 dependency):
  ⚠ TODO(blueprint-desktop-build): desktop build/flavor/signing/distribution + CI smoke-build jobs
     for Windows/Linux/macOS (docs/patterns/mobile/09).
  ⚠ TODO(blueprint-desktop-deeplinks): desktop deep-link / protocol-handler registration (13).
  ⚠ TODO(blueprint-desktop-push): desktop push strategy or documented no-op (15).
  ⚠ TODO(blueprint-desktop-multiwindow): revisit single-window vs multi-window (05/11).
  ⚠ TODO(blueprint-desktop-deps): revisit excluded desktop deps — adaptive scaffold, Linux theming (11).
  ⚠ TODO(design-desktop-fonts): desktop default-font mapping (design-system.md, splash.md).
  ⚠ TODO(design-desktop-qr): desktop QR capture approach (qr-scan.md).
  ⚠ TODO(tokens-desktop-transitions): desktop PageTransitions in generated theme (nox-handoff).
  ⚠ TODO(handoff-duplicate): reconcile/remove stray "docs/design/system/nox-handoff 2/" duplicate.
  ⚠ TODO(design-desktop-screens-reconcile): existing git-tracked desktop design corpus
     docs/design/system/nox-desktop-screens/ (mobile sibling nox-mobile-screens/) — confirm as the authoritative
     desktop screen reference under the five-platform scope; design-desktop-fonts / design-desktop-qr follow-ups
     MUST point at existing desktop specs (e.g. nox-desktop-screens/screens/06-qr.md), not treat them as net-new.
  ⚠ TODO(design-desktop-handoff): docs/design/spec/HANDOFF-PROMPT.md is framed mobile-only (iOS/Android, 393×852);
     extend to the desktop platform set / desktop window frame, aligned with nox-desktop-screens/.
-->

# Конституция проекта NOX

NOX — защищённый кросс-платформенный мессенджер (iOS, Android, Windows, Linux, macOS; Flutter) с end-to-end шифрованием; ориентир — Signal. Эта конституция фиксирует не подлежащие компромиссу принципы проекта. Она имеет приоритет над прочими практиками; работа над фичами (spec → plan → tasks → implement) проверяется на соответствие ей.

## Основные принципы

### I. Приватность и E2EE — без компромиссов

E2EE включено по умолчанию для всех сообщений и файлов; сервер не имеет доступа к содержимому, и это **нельзя отключить**. Метаданные на стороне сервера минимизируются. Идентичность анонимна — без телефона и e-mail; технический идентификатор и публичный label разделены. Клиентская аналитика, логи и крэш-репорты **никогда** не содержат PII, содержимого сообщений, идентификаторов пользователей или имён чатов; аналитика — строго opt-in (по умолчанию выключена). Logout полностью стирает идентификатор и локальные данные с устройства.

**Обоснование:** приватность — смысл продукта (Signal-like), а не фича; любое решение, ослабляющее её, отклоняется или выносится владельцу.

### II. Спецификации и дизайн-корпус — источник истины

Каждая фича проходит spec-driven цикл: spec → plan → tasks → implement. Авторитетная UI/UX-спека — `docs/design/spec/` (верхнеуровневый UI зафиксирован, экраны детализированы); продуктовые решения фиксируются там и в таблице решений, а не «на ходу». Реализация не должна расходиться со спекой; обнаруженное расхождение устраняется в том же change-set — либо код приводится к спеке, либо спека осознанно обновляется. Зафиксированный out-of-scope молча не расширяется.

**Обоснование:** проект ведётся документацией-вперёд; согласованность спеки и реализации — условие предсказуемости.

### III. Архитектурный блюпринт обязателен

`docs/patterns/mobile/` — обязательный блюпринт для всего клиентского Flutter-кода (на всех пяти целевых платформах). В начале любой Flutter/клиентской задачи — сверяться с ним и строить по нему. Несущие инварианты: один Dart-пакет `nox_app`, Clean Architecture слоями-папками (`presentation → domain ← data`, `domain` ни от чего не зависит), BLoC = Freezed, единый injectable + get_it DI, `RepositoryResult<T>` повсюду, обязательный `LogRepository` (никаких сырых `print`), codegen-first, дизайн-токены вместо хардкода. Эти инварианты платформенно-нейтральны и применяются ко всем таргетам. Платформенно-специфичные части блюпринта (build/secrets, push, deep-links, secure storage) сейчас определены для iOS/Android; перед desktop-работой в такой подсистеме блюпринт расширяется на desktop либо для неё фиксируется явный документированный desktop-fallback. Дрейф реального кода от блюпринта чинится в том же change-set (правится код либо сам блюпринт).

**Обоснование:** единый источник истины по архитектуре держит код консистентным между сессиями и контрибьюторами.

### IV. Верность дизайн-системе

UI строится на Material Design 3, light + dark. Источник истины дизайн-токенов — `docs/design/system/nox-handoff/` (формат W3C DTCG); Dart-тема генерируется из них. В коде фич **нет** хардкод-цветов, отступов, типографики и overlay-стилей — только токены. Экраны следуют зафиксированным спекам и глобальным UI-конвенциям (уровни ошибок, форматы времени, иконки типов файлов, генерируемые аватары). Brand-fixed исключения (тёмный splash, светлая поверхность QR) соблюдаются вне зависимости от темы.

**Обоснование:** единая токенизированная дизайн-система даёт консистентный UI и дешёвую темизацию.

### V. Языковая дисциплина

Документация и общение — **русский**; код, идентификаторы, имена файлов, shell-команды, сообщения коммитов, имена веток и заголовки PR — **английский**; UI-микрокопия — **английский**. Языки приложения — English + Українська (системный по умолчанию, fallback на English); русский в UI продукта не используется. Языки не смешиваются внутри одного артефакта.

**Обоснование:** русскоязычная команда ведёт прозу, но кодовая база и продукт остаются англоязычными и переносимыми.

## Технологический контекст и ограничения

- Стек — по блюпринту `docs/patterns/mobile/`: Flutter, запиненный через FVM (`3.44.1`), Dart `>=3.12.0 <4.0.0`, длина строки 140, стоковый `flutter_lints`; freezed + json_serializable + injectable + flutter_gen за один прогон `build_runner`.
- Платформы — iOS, Android, Windows, Linux, macOS (две мобильные + три десктопные). Web — вне scope. Платформенно-специфичные нативные части (сборка/секреты, push, deep-links, secure storage) сейчас покрыты блюпринтом для iOS/Android; для desktop они либо расширяются в блюпринте, либо получают явный документированный fallback (см. Принцип III).
- Бэкенд, транспортный протокол, криптоядро и модель синхронизации **намеренно ещё не выбраны**. Любой план или код, касающийся сети, авторизации, формата конверта или эндпоинтов, помечает контракт как пример/TBD и согласуется с владельцем — не «изобретается на глаз».
- Приложение пока не заскаффолжено (нет `lib/` / `pubspec.yaml`); репозиторий находится в фазе дизайна и документации.

## Рабочий процесс и гейты качества

- **Ветки:** `master` — только релизные коммиты; `develop` — рабочая ветка, от неё стартуют фиче-ветки. Рутинная работа идёт в `develop`.
- **Коммиты:** imperative-subject, атомарные, на английском. Коммиты, пуши в `develop`/`master` и merge PR **не выполняются автономно** — изменения стейджатся, показывается дифф, предлагается команда коммита и ожидается явное подтверждение владельца.
- **Гейт кода (по блюпринту):** перед завершением задачи — codegen (один прогон) → форматирование только изменённых файлов (`-l 140`) → `flutter analyze` без ошибок → затронутые тесты. Сгенерированные файлы руками не правятся.
- **Гейт фичи (spec-kit):** spec → (опц.) clarify → plan → tasks → (опц.) analyze/checklist → implement; на этапе plan выполняется Constitution Check против принципов I–V.

## Governance

Эта конституция имеет приоритет над прочими практиками проекта. Поправки требуют документированного изменения, обновления версии по семантике (ниже) и явного одобрения владельца. Все планы и PR проверяются на соответствие принципам (Constitution Check — гейт этапа plan); отклонения фиксируются и обосновываются в разделе Complexity Tracking плана либо устраняются. Усложнение требует обоснования — проще лучше.

Версионирование конституции: **MAJOR** — несовместимое изменение, удаление или переопределение принципов; **MINOR** — добавление принципа/раздела или существенное расширение; **PATCH** — уточнения и формулировки без смены смысла.

Руководства времени разработки: `CLAUDE.md` (корневые правила репозитория), `docs/patterns/mobile/` (архитектура), `docs/design/spec/` и `docs/design/system/` (UI и дизайн-система).

**Version**: 1.1.0 | **Ratified**: 2026-06-08 | **Last Amended**: 2026-06-08
