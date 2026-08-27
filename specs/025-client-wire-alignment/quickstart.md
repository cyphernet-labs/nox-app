# Quickstart: локальная проверка фичи 025

## Автоматическая валидация (основной путь)

```bash
make gate            # generate → format → analyze → test (732+ тестов)
make golden-verify   # 216 baseline — UI-поведение заморожено
```

Ключевые новые сьюты: `test/data/entity/chat/wire/` (контрактные фикстуры), `test/data/local/sync/`, `test/data/repository/sync/`, обновлённые `chat_thread_bloc_test.dart` (курсорная догрузка) и `chats_list_bloc_test.dart` (has_more).

## Снятие фикстур с живого сервера (как обновлять)

```bash
cd client_backend && go build -o noxd . && ./noxd -addr 127.0.0.1:8080 -db /tmp/nox-fixtures.db
# websocat: hello → chat.create → message.send (текст и вложение через curl PUT) → chats.list → messages.list → chat.files
# payload'ы ответов/событий (поле data) сохраняются в test/fixtures/wire/*.json как есть
```

Расхождение фикстуры и DTO чинится **в коде клиента** (Принцип VII), фикстура не редактируется.

## Ручная проверка владельцем (моки, ~5 минут)

1. `fvm flutter run --dart-define-from-file=config/stage.json` — приложение ведёт себя как раньше: список чатов, тред, догрузка старших при прокрутке вверх, отправка, вложения.
2. Перезапустить приложение — тред и список без изменений (курсор и seq персистентны).
3. Logout → Login — данные пересеяны, курсор начался заново (визуально — прежний мок-мир).

## Регрессионная сетка

Любое визуальное расхождение = провал фазы: `make golden-verify` обязан пройти без перегенерации baseline (FR-009).
