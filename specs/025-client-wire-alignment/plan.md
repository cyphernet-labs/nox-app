# Implementation Plan: client-wire-alignment

**Branch**: `025-client-wire-alignment` | **Date**: 2026-08-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/025-client-wire-alignment/spec.md`

## Summary

Данные Flutter-приложения переводятся на язык контракта v0 (§9: 1, 2, 4, 5, 7) без изменения видимого поведения: `seq` становится ключом сортировки/пагинации сообщений (тред — `before_seq`/`has_more`, список чатов — страницы с `has_more` без `total`), wire-DTO переписываются 1:1 (unix-секунды, `body`-объект, вложение `{file_id, name, size, mime, expires_at}`, без `status`/`is_system`/`unread_count`), появляются персистентный курсор `since`, `expires_at` c гейтингом Save, `limits` в data-слое и коды провода в `RepositoryException`. Верность форм закрепляется фикстурами живых кадров `noxd`. 216 голденов — регрессионная сетка: мок-минтинг `seq` обязан дать побайтово прежний видимый порядок.

## Technical Context

**Language/Version**: Dart / Flutter 3.44.1 (FVM), пакет `nox_app`

**Primary Dependencies**: без новых — freezed/json_serializable/injectable/sembast/bloc уже в проекте

**Storage**: Sembast — `messages` получает `seq` и поля вложения (`mime`, `expires_at`) **необязательными** (паттерн `attachmentLocalPath`: старые записи читаемы); новый одно-записный store `sync` (курсор `since`); `chats` получает необязательные `createdAt`/`createdByLabel` (wire их несёт)

**Testing**: `make gate` (732+ тестов) + `make golden-verify` (216 baseline); новые фикстуры `test/fixtures/wire/*.json` — живые кадры `noxd`

**Target Platform**: все пять целей; фаза чисто data-слойная + один гейт Save в `FileViewPage`

**Project Type**: Flutter-приложение, Clean Architecture по блюпринту `docs/blueprints/mobile`

**Performance Goals**: не хуже текущего (все операции локальные, Sembast)

**Constraints**: UI-поведение заморожено голденами (FR-009); мок-`seq` детерминирован под `kGoldenClock`; поля Sembast — только необязательные добавления; `field_rename: snake` — никаких Finder по camelCase; контракт v0 — закон (Принцип VII)

**Scale/Scope**: ~9 файлов домена/entity, 4 маппера, 2 DAO (+1 новый), 2 репозитория, 3 мок-генератора, 2 блока (пагинационные швы), EntityConverter, `FileViewPage`, блюпринты 04/07, ~25 файлов тестов

## Constitution Check

| Принцип | Статус | Как соблюдён |
|---|---|---|
| I. Приватность и E2EE-готовность | PASS | Данные не покидают устройство (фаза на моках); wire-слой перестаёт нести лишнее (`status`, `unread_count` уходят с провода) |
| II. Спецификация — источник истины | PASS | spec.md + артефакты фазы; блюпринты 04/07 правятся в этом же change-set (см. ниже) |
| III. Архитектурный блюпринт обязателен | PASS | Слои не меняются: домен ← data, мапперы — единственная точка коэрций; `07-pagination` §4/§5 и `04-data-layer` §1 приводятся к контрактному канону в этом change-set; carve-out `FileViewPage` (BLoC-less) расширяется одной строкой гейта — миграция на BLoC остаётся долгом фазы 027+ (зафиксировано в докстринге) |
| IV. Верность дизайн-системе | PASS | Визуал не меняется; голдены — гейт |
| V. Языковая дисциплина | PASS | Код/коммиты английские; артефакты русские; новых UI-строк нет (disabled Save — существующее состояние) |
| VI. Мобильно-десктопный паритет | PASS | Изменений вёрстки нет; обе ширины закрыты существующими голденами (20 тредовых + 12 списочных baseline) |
| VII. Контракт провода — закон | PASS | Формы §4–§7 дословно; фикстуры сняты с живого сервера; расхождение чинится в коде, не в фикстуре |

**Post-design re-check**: PASS — новых зависимостей и отступлений нет.

## Project Structure

### Documentation (this feature)

```text
specs/025-client-wire-alignment/
├── plan.md              # этот файл
├── research.md          # решения R1–R10
├── data-model.md        # дельты моделей/entity/store
├── contracts/README.md  # срез контракта фазы (что именно парсим/шлём)
├── quickstart.md        # владельческая проверка + снятие фикстур
└── tasks.md             # Phase 2
```

### Source Code (repository root, ключевые точки)

```text
lib/domain/model/chat/          # MessageModel.seq, MessageAttachment.{mime,expiresAt}, ChatModel.{createdAt,createdByLabel}
lib/domain/repository/base/     # PageMetadata → {hasMore, nextPage?}
lib/domain/repository/chat/     # GetMessagesConfig → {chatId, beforeSeq?, limit}
lib/domain/repository/sync/     # NEW: SyncRepository (курсор since)
lib/domain/model/app_config/    # ServerLimits (+ AppConfig.limits)
lib/domain/exception/           # RepositoryException + коды провода §2.1
lib/data/entity/chat/           # MessageEntity.{seq,attachmentMime,attachmentExpiresAt}; ChatEntity.{createdAt,createdByLabel}
lib/data/entity/chat/wire/      # ПЕРЕПИСАНЫ 1:1: MessageWireEntity, BodyWireEntity, AttachmentWireEntity, ChatWireEntity, страницы {messages|chats, has_more}
lib/data/entity/base/           # ResponseEntity.error → ErrorWireEntity{code,message}; EntityConverter — перерегистрация
lib/data/mapper/chat/           # оба storage-маппера + оба wire-маппера
lib/data/local/chat/            # MessageDao сортировка по seq; NEW lib/data/local/sync/sync_dao.dart
lib/data/repository/chat/       # обе пагинации; курсор-запись; error-коды из envelope
lib/data/repository/sync/       # NEW: SyncRepositoryImpl
lib/data/remote/api/chat/       # генераторы: контрактные формы + минтинг seq
lib/presentation/pagination/    # PagingStateExt: isLastPage = !hasMore
lib/presentation/pages/.../bloc # ChatThreadBloc (oldestSeq вместо nextPage), ChatsListBloc (hasMore), ItemListBloc (компиляционная правка мёртвого среза)
lib/presentation/pages/file_view_page/  # гейт Save по expiresAt
docs/blueprints/mobile/         # 07-pagination §4/§5, 04-data-layer §1 — контрактный канон
test/fixtures/wire/*.json       # живые кадры noxd
```

**Structure Decision**: без новых архитектурных элементов, кроме пары `SyncDao`/`SyncRepository` (курсор — данные устройства, живёт и гибнет с локальной базой) и модели `ServerLimits` в `AppConfig` (in-memory, контрактные дефолты; писатель появится в 027).

## Complexity Tracking

Нарушений нет — секция пуста.
