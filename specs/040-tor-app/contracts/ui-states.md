# Контракт интерфейса: состояние связи, бейдж Tor, тексты

Решение владельца (Clarifications, 2026-10-03): показываются только отклонения от обычного.

## Место

| Ширина | Где |
|---|---|
| Узкая (< `Constants.railBreakpoint`) | справа в верхней панели списка чатов (5.1) — перед аватаром аккаунта; справа в верхней панели переписки (5.2) — перед действием приглашения |
| Широкая | правый край заголовка окна (`AppWindowTitlebarWidget`) в оболочке `TabBarShell` — виден на всех экранах оболочки |

## Состояния

| `ConnectionStatus` | Угол | Баннер |
|---|---|---|
| `online` + `direct` | пусто | — |
| `online` + `tor` | бейдж `Tor` | — |
| `connecting` / `catchingUp` + путь не выбран или `direct` | `Connecting…` | — |
| `connecting` / `catchingUp` + `tor` | `Connecting…` + бейдж `Tor` | — |
| `offline` | пусто | `No connection` (нынешний) |
| `serverMismatch` | пусто | `This isn't the server you paired with` (нынешний) |
| `torObsolete` (любое состояние) | как выше | `Update NOX to connect away from home` |

Бейдж и текст строятся на токенах: `AppDimensionTokens` и `AppSpacingTokens` для размеров, роли `Theme.of(context).textTheme` — `labelSmall` для бейджа, `labelMedium` для «Connecting…» (у них проектная высота строки), цвета `ColorScheme` — `secondaryContainer`/`onSecondaryContainer` для бейджа, `onSurfaceVariant` для текста. Хардкода нет (Принцип IV).

## Нажатие

Индикатор нажимается всегда, когда видим. Область касания не меньше 48×48 (FR-029); в заголовке окна на широкой ширине её высота — высота заголовка (44), ширина — не меньше 48. Нажатие открывает пояснение: на узкой ширине — нижний лист, на широкой — диалог.

## Тексты (EN / UK)

| Ключ ARB | EN | UK |
|---|---|---|
| `connectionTorBadge` | Tor | Tor |
| `connectionConnecting` | Connecting… | Підключення… |
| `connectionSemanticsTor` | Connected through Tor | Підключено через Tor |
| `connectionSemanticsConnecting` | Connecting to your server | Підключення до вашого сервера |
| `connectionSemanticsConnectingTor` | Connecting to your server through Tor | Підключення до вашого сервера через Tor |
| `connectionInfoTitle` | Connection | З'єднання |
| `connectionInfoTor` | NOX can't reach your server directly, so it connects through Tor. It's slower, but it works from any network. | NOX не може дістатися до вашого сервера напряму, тож підключається через Tor. Це повільніше, але працює з будь-якої мережі. |
| `connectionInfoConnecting` | NOX is connecting to your server. | NOX підключається до вашого сервера. |
| `connectionInfoLocalNetwork` | If you're at home, check that NOX has Local Network access in Settings. | Якщо ви вдома, перевірте, що NOX має доступ до локальної мережі в Параметрах. |
| `connectionTorObsolete` | Update NOX to connect away from home | Оновіть NOX, щоб підключатися поза домом |
| `devicesInviteHomeOnly` | This link works only on your home network. | Це посилання працює лише у вашій домашній мережі. |
| `loginHomeNetworkOnly` | Couldn't reach your server. Pairing works on your home network. | Не вдалося зв'язатися з вашим сервером. Звʼязування працює у вашій домашній мережі. |

`connectionInfoLocalNetwork` показывается только на iOS и macOS.

## Голдены

Голдены светлой и тёмной темы, по паре на каждый:

- **Виджет индикатора**: пусто, `Tor`, `Connecting…`, `Connecting…` + `Tor`.
- **5.1 и 5.2, узкая ширина**: `online(tor)`, `connecting(tor)`.
- **Оболочка, широкая ширина**: заголовок окна с `online(tor)` и с `connecting(tor)`.
- **Карточка приглашения**: с пометкой «только дома».
- **Баннер устаревшего Tor** на 5.1: обе ширины.
