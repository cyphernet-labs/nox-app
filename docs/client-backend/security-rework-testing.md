# Как поднять и проверить NOX: трек безопасности 044–050

Документ описывает, как на Mac поставить сервер NOX вместе с tor скриптом установки, запустить приложение на двух-трёх симуляторах iOS (и, по желанию, на телефоне) и по шагам проверить трек безопасности. Сценарии охватывают фичи 044–050: защищённый канал — TLS 1.3 и проверку `POST /auth` → `POST /auth2` с ключами и подписями RustSecureBox (050; в этой сборке RustSecureBox — заглушка, и сервер об этом предупреждает), спаривание с подтверждением, запертый сервер и пароль, Tor, бэкап, шифрование данных на сервере и на устройстве, обновление сервера скриптом — в том числе с перевыпуском ключа сервера и повторным спариванием устройств, когда ключ сделала другая реализация RustSecureBox.

Подробности про установку — [deploy/README.md](../../deploy/README.md), про стенд для показа — [demo-runbook.md](demo-runbook.md).

## Что получится

- **Сервер** — службы macOS: `noxd` (порт `8443`, служебная страница `http://127.0.0.1:8081`) и отдельная служба tor с onion-сервисом NOX. Данные сервера зашифрованы, после каждого запуска сервер заперт до ввода пароля.
- **Устройства** — приложение на симуляторах iOS: первое спаривается по ссылке с машины сервера, второе и третье — по приглашению с первого.
- Всё работает в домашней сети напрямую; путь через Tor проверяется на симуляторе (спаривание через Tor) и, по желанию, на телефоне в мобильной сети.

## 1. Подготовка

Нужно: Xcode с симуляторами iOS, Go (тот, что в `client_backend/go.mod`), fvm с Flutter 3.44.1, Rust через rustup, gpg (`brew install gnupg`) — им скрипт проверяет подпись Tor Project. tor ставить не надо: скрипт скачает Tor Expert Bundle сам.

**Перейти на ветку `develop`** — в папке проекта:

```bash
git switch develop && git pull
```

**Остановить старый демо-стенд**, если он работает: он держит порты `8080` и `8081`, а служебной странице установленного сервера нужен `8081`.

```bash
pkill -f /tmp/nox-demo-noxd; pkill -f /tmp/nox-demo/torrc
lsof -nP -iTCP:8081 -sTCP:LISTEN; lsof -nP -iTCP:8443 -sTCP:LISTEN     # пусто - порты свободны
```

**Сгенерировать код приложения** (сгенерированные файлы не хранятся в git):

```bash
make deps && make generate
```

**Завести три отдельных симулятора** — чистых, без старой установки NOX и без чужих приложений; свои симуляторы стирать не нужно. Каждая команда печатает UDID нового симулятора:

```bash
xcrun simctl list runtimes available                     # какие iOS есть, например iOS-18-5
xcrun simctl create NOX-1 com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-18-5
xcrun simctl create NOX-2 com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro com.apple.CoreSimulator.SimRuntime.iOS-18-5
xcrun simctl create NOX-3 com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-18-5
```

После проверки их убирает `xcrun simctl delete <UDID>`.

## 2. Запустить сборку приложения

Первая сборка идёт несколько минут (Rust-модуль под симулятор, CocoaPods), поэтому её запускают сразу, а сервер ставят, пока она идёт. Терминал **B**:

```bash
open -a Simulator
xcrun simctl boot <UDID NOX-1>
fvm flutter run -d <UDID NOX-1> --dart-define-from-file=config/stage.json
```

`--dart-define-from-file=config/stage.json` обязателен: без него приложение работает с выдуманными данными и к серверу не ходит.

## 3. Поставить сервер

Терминал **A**:

```bash
sudo deploy/install-macos.sh
```

Скрипт:

1. Проверяет права, порты `8443` и `8081`, собирает `noxd` из репозитория.
2. Спрашивает **пароль сервера** дважды — не короче 12 знаков. Пароль нигде не сохраняется и не восстанавливается: забытый пароль — потерянные данные сервера. Запишите его.
3. Спрашивает публичный адрес — **Enter** (его нет).
4. Скачивает Tor Expert Bundle, проверяет подпись Tor Project, запускает tor и ждёт onion-адрес (до минуты).
5. Ставит и запускает сервер, задаёт ему пароль.
6. Печатает **ссылку** `nox://pair/…` и QR-код для первого устройства (живут 10 минут), адрес служебной страницы, как открыть сервер после перезагрузки и где папка бэкапов. Если брандмауэр macOS включён — команду, которая пускает к серверу телефоны.

macOS покажет уведомление о новых фоновых объектах — это службы NOX.

Проверить:

```bash
curl -s http://127.0.0.1:8081/health                                    # {"status":"ok"}
sudo launchctl print system/com.cyphernetlabs.noxd | grep "state ="     # running
sudo launchctl print system/com.cyphernetlabs.nox-tor | grep "state ="  # running
sudo grep -c "RustSecureBox is a stub" /Library/Logs/NOX/noxd.log      # 1 или больше
open http://127.0.0.1:8081
```

На служебной странице — QR-код, та же ссылка текстом, `Expires in 10 minutes`, ниже — адреса (найденный в сети и onion) с кнопками `Set` и смена пароля.

Вверху страницы — строка `RustSecureBox is a stub: devices are not really verified.`, а в журнале сервера при каждом запуске, как только пароль открыл сервер, — предупреждение `RustSecureBox is a stub: devices are not really verified`. Так и должно быть: в этой сборке RustSecureBox — заглушка. С настоящим RustSecureBox оба предупреждения пропадают сами.

Ссылка истекла, пока шла сборка, — новую дают `noxd link -qr` (без `sudo`) или `New link` на странице. Новая гасит прежнюю.

## 4. Проверки

Для проверки шифрования заведите **метку** — слово, которого больше нигде нет, например `Kiwi-7319`, — и пишите его в сообщениях.

### 4.1. Первое устройство — ссылка с машины (044, 046)

1. В приложении на NOX-1: скопировать ссылку из терминала, в поле `Pairing link` — `Paste` (или Cmd+V) → `Sign in`.
2. Экран **`Connect to your server`**: `Server address` (адрес Mac в сети с портом `8443`) и `Onion address` подставлены из ссылки, `Use Tor` выключен → `Connect`.
3. Экран имени → имя → список чатов.
4. Обновить служебную страницу: ссылки больше нет, вместо неё — `Add a device`.

Ожидается: спаривание за секунду-две, ключа сервера на экране нет — приложение сверяет его само. Строка `RustSecureBox is a stub: devices are not really verified.` вверху служебной страницы и предупреждение о заглушке в журнале сервера остаются (раздел 3): проверка `/auth` и `/auth2` проходит и с заглушкой, но с ней стороны по-настоящему не проверяются.

### 4.2. Переписка и файлы

1. `+` → создать чат → отправить сообщение с меткой, картинку (в симуляторе есть фото в «Фото»), любой файл.
2. Закрыть приложение в симуляторе (смахнуть вверх) и открыть снова → вход без спаривания, всё на месте.

### 4.3. Второе устройство — приглашение с подтверждением (046)

Терминал **C**:

```bash
xcrun simctl boot <UDID NOX-2>
fvm flutter run -d <UDID NOX-2> --dart-define-from-file=config/stage.json
```

**Отказ.** На первом: `Settings` → `Devices` → `Add a device` → QR и ссылка → `Copy`. На втором: `Paste` → `Sign in` → `Connect` → `Waiting for approval on your other device`. На первом поверх экрана: `New device: iPhone or iPad. Allow it to join?` → `Deny`. Второе: `Your other device declined this request.`

**Отмена.** Новое приглашение на первом → на втором предъявить его и, пока ждёт, нажать `Cancel` → вопрос на первом закрывается сам.

**Разрешение.** Новое приглашение → предъявить → на первом `Allow`. Второе входит **той же личностью и без выбора имени**, видит все чаты; список `Devices` обновился на обоих.

### 4.4. Свои устройства пишут друг другу

1. Сообщение с первого приходит на второе **своим**: то же имя автора, та же сторона, тот же значок статуса.
2. Закрыть приложение на втором, написать с первого, открыть второе — пропущенное доходит, без дублей и в том же порядке.

### 4.5. Запертый сервер и пароль (047)

```bash
sudo launchctl kickstart -k system/com.cyphernetlabs.noxd     # перезапуск сервера
curl -s http://127.0.0.1:8081/health                           # {"status":"locked"}
```

1. Приложения показывают плашку без связи: `No connection` или, поскольку onion-адрес известен, а `Use Tor` выключен, — `Can't reach the server directly. Turn on Use Tor to connect through Tor.`
2. Служебная страница — только поле пароля: ни ссылки, ни адресов.
3. `noxd unlock` → неверный пароль → `Wrong password.`
4. `noxd unlock` → верный → `Unlocked.` Приложения подключаются сами, ничего не потеряно и не стёрто. Так же — полем на странице.
5. **Смена пароля:** `noxd password` (текущий, новый, повтор) → снова `kickstart -k` → открывает только новый.

### 4.6. Данные сервера на диске зашифрованы (047)

```bash
sudo grep -rl "Kiwi-7319" "/Library/Application Support/NOX"; echo "exit $?"   # ничего не найдено, exit 1
```

### 4.7. Бэкап (047)

Бэкап пишет сам работающий сервер, и только в свою папку:

```bash
noxd backup "/Library/Application Support/NOX/backups/nox-test.tar"
sudo cp "/Library/Application Support/NOX/backups/nox-test.tar" ~/ && sudo chown "$USER" ~/nox-test.tar
grep -c "Kiwi-7319" ~/nox-test.tar          # 0 - внутри всё зашифровано
```

Восстановление — по разделу «Восстановление» в [deploy/README.md](../../deploy/README.md): остановить сервер, отложить нынешнюю базу, `noxd restore` от имени `_nox`, запустить, открыть паролем бэкапа. Устройства подключаются без спаривания и перечитывают переписку; то, что они не успели отправить, при этом стирается — перед бэкапом дайте им всё отправить.

### 4.8. Tor (045)

На одной машине «уйти из дома» нельзя: приложение пробует все прямые адреса сервера, какие знает. Поэтому путь через Tor проверяют на новом устройстве, которому дали только onion-адрес, или на телефоне в мобильной сети.

**Спаривание через Tor (симулятор).** Терминал **D**: загрузить NOX-3 и запустить приложение, как в 4.3. На первом — новое приглашение и `Copy`. На третьем — `Paste` → `Sign in` → на экране подключения:

- `Server address` заменить на `192.0.2.1:8443` — адрес, на котором никто не отвечает;
- `Onion address` оставить;
- `Use Tor` включить → `Connect`.

Ожидается: первый подъём Tor — от нескольких секунд до минуты, затем `Waiting for approval on your other device` → `Allow` на первом → третье устройство в чатах, в углу бейдж `Tor`. Сообщения ходят через Tor. Сервер в приветствии сообщает свои домашние адреса, и самое позднее через 2 минуты приложение уходит на прямой путь — бейдж `Tor` пропадает.

**Причины на экране подключения.** На другом приглашении, с тем же недоступным `Server address`:

| Что сделать | Что видно под `Connect` |
|---|---|
| `Use Tor` выключен | `Can't reach the server directly. Turn on Use Tor to connect through Tor.` |
| В `Onion address` вписать что-то неправильное | `This isn't a valid onion address.` |
| Остановить tor сервера: `sudo launchctl bootout system/com.cyphernetlabs.nox-tor` | `Your server isn't answering through Tor right now. Check that it is running.` — пока описание сервиса ещё лежит в каталогах Tor; позже — `No server answers at this onion address. Check the address and that Tor is running on the server.` |

Вернуть tor: `sudo launchctl bootstrap system /Library/LaunchDaemons/com.cyphernetlabs.nox-tor.plist`.

**Телефон вне дома** (по желанию; подготовка телефона — в разделе 5). Спарить телефон дома. Выключить Wi-Fi (мобильный интернет) при выключенном `Use Tor` → `Can't reach the server directly. Turn on Use Tor to connect through Tor.` → `Settings` → `Connection` → включить `Use Tor` → подключение через Tor, бейдж `Tor`, переписка идёт. Включить Wi-Fi дома → прямой путь при смене сети, самое позднее через 2 минуты.

### 4.9. Связь в настройках (045)

`Settings` → `Connection`: адрес сервера, onion-адрес и `Use Tor` — те же, что на экране подключения; `Use Tor` применяется сразу. Неверный адрес — сообщение у поля, ничего не меняется.

### 4.10. Отзыв и выход (046)

1. На первом: `Settings` → `Devices` → третье устройство → `Revoke` → подтвердить. Третье сразу теряет связь, а при следующем подключении стирает свои данные и возвращается к экрану спаривания.
2. `Settings` → `Log out` на всех устройствах. Служебная страница снова сразу показывает ссылку с машины. Спарить по ней устройство — оно видит **всю прежнюю переписку**: человек тот же.

### 4.11. Данные на устройстве зашифрованы (048)

```bash
DATA=$(xcrun simctl get_app_container <UDID NOX-1> com.cyphernetlabs.noxapp data)
grep -rl "Kiwi-7319" "$DATA/Library/Application Support"; echo "exit $?"   # ничего не найдено, exit 1
```

### 4.12. Обновление сервера скриптом (049)

```bash
sudo deploy/install-macos.sh
```

Скрипт видит установленный сервер: `a NOX server is installed here: this run updates it…`. Пароль он не спрашивает, сервер перезапускается запертым — `noxd unlock`. Переписка, устройства, onion-адрес и ключ сервера на месте, спаривать заново не нужно.

Исключение — сервер, поставленный сборкой до 050. Такое обновление один раз перевыпускает ключ сервера; в журнале — `server key was made by another RustSecureBox: every device pairs again`. Все устройства спариваются заново ссылкой с машины: после `noxd unlock` служебная страница сразу её показывает. Переписка сохраняется, и спаренное заново устройство видит её целиком. Приложение один раз возвращает к спариванию и при этом стирает то, что не успело отправить, — до обновления дайте устройствам всё отправить.

### 4.13. Перезагрузка (по желанию)

Перезагрузить Mac → сервер и tor поднимаются сами, сервер заперт → `noxd unlock` или страница → устройства на связи.

## 5. Другие устройства (по желанию)

- **iPhone.** Команды разработчика в проекте нет. В Xcode открыть `ios/Runner.xcworkspace` → цель `Runner` → `Signing & Capabilities` → выбрать свою команду, подпись автоматическая; это изменение проекта не коммитят. Подключить телефон, затем `fvm flutter devices` и `fvm flutter run -d <id телефона> --dart-define-from-file=config/stage.json`. Телефон — в той же Wi-Fi-сети, что Mac; при первом запуске разрешить доступ к локальной сети. Ссылку удобно снять с экрана: `Scan QR` на экране входа.
- **Приложение для macOS.** `fvm flutter run -d macos --dart-define-from-file=config/stage.json`. Отладочная сборка подписывается без команды и держит ключи в обычной связке ключей (login keychain); связку ключей с защитой данных использует только релизная сборка, подписанная командой.
- **Android.** Нужен NDK `28.2.13676358`; телефон в той же Wi-Fi-сети или эмулятор; `fvm flutter run -d <id> --dart-define-from-file=config/stage.json`.

## 6. Если что-то не так

| Симптом | Что делать |
|---|---|
| `port 8081, for the service page, is in use by …` | Работает старый стенд — раздел 1, или поставить с `--status-port 9081` (тогда командам нужен `-status-addr 127.0.0.1:9081`) |
| `tor: there is no gpg …` | `brew install gnupg` и запустить скрипт ещё раз: сервер обновится, tor добавится |
| `This link has expired. Ask for a new one.` | `noxd link -qr` или `New link` на странице |
| `This link can't be used. Ask for a new one.` | Ссылку уже использовали или её погасила более новая — выдать новую |
| Приложение не подключается, плашка `No connection` | `curl -s http://127.0.0.1:8081/health`: `locked` — сервер заперт, `noxd unlock`; нет ответа — служба не запущена (журнал — `/Library/Logs/NOX/noxd.log`) |
| `noxd unlock` пишет `no server answered on …` | Служба сервера не запущена или страница на другом порту |
| Телефон в Wi-Fi не подключается | Брандмауэр macOS: команду печатает скрипт (`socketfilterfw --add /usr/local/bin/noxd --unblockapp …`); на iPhone — доступ к локальной сети в настройках |
| tor не записал onion-адрес | Конец журнала — `/Library/Logs/NOX/tor.log` |
| Приложение на симуляторе сразу просит спаривания или висит без связи | Осталась старая установка: удалить приложение (`xcrun simctl uninstall <UDID> com.cyphernetlabs.noxapp`) или взять новый симулятор (раздел 1) |

## 7. Убрать всё с Mac после проверки

Данные сервера, его ключ и onion-адрес удаляются насовсем; после новой установки все устройства спариваются заново.

```bash
sudo launchctl bootout system/com.cyphernetlabs.noxd
sudo launchctl bootout system/com.cyphernetlabs.nox-tor
sudo rm -f /Library/LaunchDaemons/com.cyphernetlabs.noxd.plist /Library/LaunchDaemons/com.cyphernetlabs.nox-tor.plist /usr/local/bin/noxd
sudo rm -rf "/Library/Application Support/NOX" /Library/Logs/NOX /usr/local/libexec/nox-tor /usr/local/etc/nox-tor /usr/local/var/lib/nox-tor /usr/local/var/run/nox /var/db/nox-install
sudo dscl . -delete /Users/_nox;    sudo dscl . -delete /Groups/_nox
sudo dscl . -delete /Users/_noxtor; sudo dscl . -delete /Groups/_noxtor
```
