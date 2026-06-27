# Contract: Account avatar (desktop rail)

UI-контракт нового аккаунт-аватара и его pure-util инициалов.

## `noxAccountInitials(String label) → String?`

Расположение: `lib/design/theme/nox_brand.dart` (рядом с `noxInitials`/`noxAvatarColor`).

**Поведение:**
- Токенизация `label.trim()` по `RegExp(r'[\s._-]+')`, пустые токены отброшены.
- Первая `[A-Za-z0-9]`-буква токена. ≥2 токенов → первая + последняя (uppercase, 2 буквы). 1 токен → 1 буква. Нет валидных букв → `null`.

**Контракт-тесты** (`test/design/theme/nox_account_initials_test.dart`, обычный `*_test.dart`, без `@Tags`):

| Вход | Ожидание |
|---|---|
| `User7421` | `U` |
| `john.doe` | `JD` |
| `john_doe_smith` | `JS` |
| `a-b-c` | `AC` |
| `Alice` | `A` |
| `nox.core.team` | `NT` |
| `  spaced  name ` | `SN` |
| `` | `null` |
| `...` | `null` |

## `AppAvatarWidget` — расширение

Добавляется опциональный `final String? initials;`.
- `initials == null` (дефолт) → текущее поведение (`noxInitials(name)`). **Существующие вызовы не меняются.**
- `initials != null` → рисуется переданная строка (uppercase, тот же стиль: `Colors.white`, `fontSize: size*0.4`, `w500`).
- Фон всегда `noxAvatarColor(name)`.

**Инвариант:** визуально идентичен аватарам чатов; отличается только источником инициалов.

## Виджет аккаунт-аватара в rail

- Рендерится в `NavigationRail.trailing` через `Expanded(child: Align(alignment: Alignment.bottomCenter, child: …))` → прижат к низу rail.
- Кликабелен (`InkResponse`/`IconButton`), tooltip `Account`, семантика — кнопка.
- Вызывает `AppAvatarWidget(name: label, initials: noxAccountInitials(label), size: AppDimensionTokens.size.avatarSm)` (U2: размер зафиксирован = `avatarSm`, как строки чатов; допускается точечная подгонка к ширине rail по итогам desktop-аудита T004).
- Виден **только** в широкой вёрстке (rail). В bottom-bar отсутствует.
- Только дизайн-токены (размер/отступы), без хардкода.

## Acceptance

- FR-008/009/010/011 (spec).
- `noxAccountInitials` зелёный на таблице выше.
- Widget-golden rail с аватаром (light+dark) — см. `golden-coverage.md`.
