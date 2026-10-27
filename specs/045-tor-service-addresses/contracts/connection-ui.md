# Контракт: экран подключения, раздел «Связь», причины неудач

UI-микрокопия — английская и украинская (`lib/l10n/app_en.arb`, `app_uk.arb`, ключи — в обоих). Обе ширины.

## Экран подключения (после ссылки: вставка, скан, картинка)

| Элемент | EN | UK |
|---|---|---|
| Заголовок | `Connect to your server` | `Під'єднання до вашого сервера` |
| Поле | `Server address` | `Адреса сервера` |
| Поле | `Onion address` | `Onion-адреса` |
| Подсказка onion (пусто) | `Optional` | `Необов'язково` |
| Галочка | `Use Tor` | `Використовувати Tor` |
| Подпись под галочкой | `NOX uses Tor only when it can't reach your server directly.` | `NOX використовує Tor, лише коли не може зв'язатися з сервером напряму.` |
| Кнопка | `Connect` | `Під'єднатися` |
| Неверный адрес сервера | `This isn't a valid server address.` | `Це неправильна адреса сервера.` |

Ключ сервера не показывается. Отказы токена и срока — те же строки, что на экране входа.

## Раздел «Связь» в настройках

| Элемент | EN | UK |
|---|---|---|
| Строка и заголовок | `Connection` | `Зв'язок` |
| Поля и галочка | как на экране подключения | |
| Кнопка | `Save` | `Зберегти` |

`Save` активна, когда значение изменено и проходит проверку формата; `Use Tor` применяется сразу.

## Причины неудач

| Причина | EN | UK |
|---|---|---|
| `invalidOnion` | `This isn't a valid onion address.` | `Це неправильна onion-адреса.` |
| `onionNotFound` | `No server answers at this onion address. Check the address and that Tor is running on the server.` | `За цією onion-адресою не відповідає жоден сервер. Перевірте адресу і чи працює Tor на сервері.` |
| `onionUnreachable` | `Your server isn't answering through Tor right now. Check that it is running.` | `Ваш сервер зараз не відповідає через Tor. Перевірте, чи він працює.` |
| `otherServer` | `This onion address belongs to a different server.` | `Ця onion-адреса належить іншому серверу.` |
| `torNetwork` | `Can't connect to the Tor network. Check your internet connection.` | `Не вдається під'єднатися до мережі Tor. Перевірте підключення до інтернету.` |
| `turnOnTor` | `Can't reach the server directly. Turn on Use Tor to connect through Tor.` | `Не вдається зв'язатися з сервером напряму. Увімкніть «Використовувати Tor», щоб під'єднатися через Tor.` |

Где видна: баннер «нет связи» на 5.1, 5.2, 5.4 — вместо `No connection`, когда причина известна (кнопка `Try again` остаётся; `otherServer` заменяет прежний баннер «не тот сервер»); раздел «Связь» — строка над полями; экран подключения — под `Connect`; `invalidOnion` — у самого поля.
