# Установка сервера NOX

Сервер NOX ставится на машину владельца одним запуском скрипта — по скрипту на систему. Скрипт ставит сервер и tor, включает onion-сервис NOX с защитой PoW и пределом потоков на цепочку, спрашивает пароль сервера, включает автозапуск обоих и в конце показывает ссылку и QR-код для первого устройства. tor — отдельная служба системы: сервер его не запускает и знает только onion-адрес, который скрипт передаёт ему параметром `-onion-addr`.

| Система | Скрипт | Автозапуск | tor |
|---|---|---|---|
| Linux | `deploy/install-linux.sh` | systemd, служба `noxd` | пакет `tor` дистрибутива, если он 0.4.9 или новее и умеет PoW; иначе — из репозитория Tor Project |
| macOS | `deploy/install-macos.sh` | launchd, `com.cyphernetlabs.noxd` | Tor Expert Bundle от Tor Project, своя служба `com.cyphernetlabs.nox-tor` |
| Windows | `deploy/install-windows.ps1` | служба Windows `noxd` | Tor Expert Bundle от Tor Project, своя служба `nox-tor` |

## Что нужно

- Права администратора.
- Сервер: Go той версии, что в `client_backend/go.mod`, — скрипт собирает `noxd` из этого репозитория. Без Go — готовый `noxd` под эту систему: `--binary` (`-Binary` на Windows).
- tor на macOS и Windows: `gpg` или `gpgv` — им проверяется подпись Tor Project (macOS: `brew install gnupg` или GPG Suite; Windows: Gpg4win). Без проверки tor не ставится: сервер ставится без него и работает напрямую.
- Интернет — для tor.

## Запуск

```bash
sudo deploy/install-linux.sh
sudo deploy/install-macos.sh
```

```powershell
# PowerShell, запущенный от имени администратора
powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1
```

Скрипт спрашивает пароль сервера дважды — не короче 12 знаков; короткий или не совпавший спрашивается снова. Пароль нигде не сохраняется и попадает к серверу только через стандартный ввод `noxd unlock`. Забытый пароль — потерянные данные: открыть их не может никто. Потом скрипт спрашивает публичный адрес машины (`host:port`), если до неё можно достучаться из интернета, — Enter, если такого нет.

Без терминала — когда стандартный ввод перенаправлен — пароль читается из него двумя строками, пароль и повтор, а публичный адрес не спрашивается. На Windows эти строки — в UTF-8 (файл UTF-16 с BOM тоже читается). Windows PowerShell 5.1 передаёт в конвейер только ASCII и заменяет остальные знаки на `?`, поэтому файл с паролем подают перенаправлением `cmd` — `cmd /c "powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1 < pw.txt"` — или из PowerShell 7.

В конце — ссылка и QR-код для первого устройства (живут 10 минут), адрес служебной страницы и то, как открыть сервер после перезагрузки.

| Linux, macOS | Windows | Что |
|---|---|---|
| `--port N` | `-Port N` | порт сервера; по умолчанию 8443, при обновлении — прежний; на Linux — не ниже 1024 |
| `--status-port N` | `-StatusPort N` | порт служебной страницы, только для этой машины; по умолчанию 8081; на Linux и macOS — не ниже 1024 |
| `--public-addr H:P` | `-PublicAddr H:P` | публичный адрес машины, если он есть |
| `--binary PATH` | `-Binary PATH` | готовый `noxd` вместо сборки; на macOS ставится его копия без карантина, который macOS вешает на файл, пришедший через AirDrop, почту или браузер |
| `--no-tor` | `-NoTor` | без tor: устройства подключаются только напрямую |
| `--tor-bin PATH` | `-TorBin PATH` | свой tor 0.4.9+ с PoW вместо скачанного (macOS, Windows; на Linux — только для проверки с `--prefix`); на Windows он копируется вместе с библиотеками рядом в `C:\Program Files\NOX\tor\` — учётная запись службы tor не читает папки владельца |
| `--prefix DIR` `--no-service` | `-Prefix DIR` `-NoService` | проверка скрипта без изменения системы, см. ниже |

## Что делает скрипт

1. Проверяет права, свободные порты и бинарник — до любых изменений. Занятый порт, нехватка прав, короткий или не совпавший пароль останавливают скрипт с понятным сообщением, и машина остаётся как была.
2. Собирает `noxd` (или берёт `--binary`) и спрашивает пароль и публичный адрес.
3. Заводит учётную запись службы (`nox` на Linux, `_nox` на macOS, `NT SERVICE\noxd` на Windows) и папку данных, доступную только ей; кладёт бинарник.
4. tor: находит подходящий или ставит — с проверкой подписи Tor Project, — пишет настройки onion-сервиса NOX, запускает tor и ждёт onion-адрес (до 60 секунд). Не вышло — скрипт говорит, что именно, убирает то, что успел сделать для tor, и ставит сервер без него.
5. Регистрирует службу сервера с адресами в параметрах запуска (`-onion-addr`, `-public-addr`) и запускает её; ждёт ответа служебной страницы. Не дождался — откатывает всё сделанное этим запуском.
6. Задаёт серверу пароль (`noxd unlock`, пароль — на стандартный ввод) и печатает ссылку и QR-код (`noxd link -qr`).

Ссылка печатается только на экран и нигде не сохраняется. Если она истекла, пока искали телефон, новую дают кнопки `Add a device` / `New link` на служебной странице или `noxd link -qr`.

Порт ниже 1024 скрипт не принимает там, где учётная запись сервера не может его слушать: на Linux — оба порта (службе не дано `CAP_NET_BIND_SERVICE`), на macOS — порт служебной страницы (macOS пускает на порты ниже 1024 без root только на всех адресах сразу, а страница слушает loopback). Чтобы устройства из интернета шли на 443, на роутере 443 пробрасывают на порт сервера.

## После перезагрузки

Сервер и tor запускаются сами. Сервер стартует запертым: данные на диске зашифрованы, и пока пароль не введён, устройства не подключаются. Ввести пароль:

- на служебной странице — `http://127.0.0.1:8081` на этой машине;
- в терминале — `noxd unlock` (права администратора не нужны); на Windows — `& 'C:\Program Files\NOX\noxd.exe' unlock`.

Если порт служебной страницы не 8081, командам нужен `-status-addr 127.0.0.1:<порт>`.

## Повторный запуск

Скрипт на машине, где сервер уже стоит, обновляет его: заменяет бинарник, переписывает службу и настройки onion-сервиса NOX и перезапускает. База, файл ключа данных (`nox.db.key`), пароль и ключ onion-адреса остаются как были; новая база поверх существующей не создаётся. Порт, порт служебной страницы и публичный адрес берутся из установленной службы, если их не передали заново. Пароль не спрашивается: после обновления сервер заперт, его открывают как после перезагрузки.

Сервер, поставленный с `--no-tor`, получает tor при повторном запуске без этого флага: onion-адрес приходит в базу, подключённые устройства получают его сразу, остальные — при следующем подключении напрямую. Переспаривать не нужно.

## Проверка без изменения системы

```bash
deploy/install-macos.sh --prefix /path/to/check --no-service --port 18443 --status-port 18081
deploy/install-linux.sh --prefix /path/to/check --no-service --tor-bin /path/to/tor
```

Все файлы — под `--prefix`, без учётных записей, без launchd, systemd и служб Windows, без пакетов и правил брандмауэра; сервер и tor работают фоновыми процессами того, кто запустил скрипт, а описания служб пишутся под префикс для просмотра. Скрипт в конце печатает, как остановить процессы. Флаги идут только вместе.

## Где что лежит

| | Linux | macOS | Windows |
|---|---|---|---|
| Сервер | `/usr/local/bin/noxd` | `/usr/local/bin/noxd` | `C:\Program Files\NOX\noxd.exe` |
| Данные | `/var/lib/nox` | `/Library/Application Support/NOX` | `C:\ProgramData\NOX` |
| Журнал сервера | `journalctl -u noxd` | `/Library/Logs/NOX/noxd.log` | `C:\ProgramData\NOX\noxd.log` |
| Служба сервера | `/etc/systemd/system/noxd.service` | `/Library/LaunchDaemons/com.cyphernetlabs.noxd.plist` | служба `noxd` |
| tor | пакет `tor`, служба `tor` | `/usr/local/libexec/nox-tor/tor`, `/Library/LaunchDaemons/com.cyphernetlabs.nox-tor.plist` | `C:\Program Files\NOX\tor\tor.exe`, служба `nox-tor` |
| Настройки tor | `/etc/tor/torrc` + `/etc/tor/nox-tor.conf` | `/usr/local/etc/nox-tor/` | `C:\ProgramData\NOX\tor\` |
| Ключ onion-адреса | `/var/lib/tor/nox/` | `/usr/local/var/lib/nox-tor/nox/` | `C:\ProgramData\NOX\tor\nox\` |
| Журнал tor | `journalctl -u tor@default` (Debian, Ubuntu) или `-u tor` | `/Library/Logs/NOX/tor.log` | `C:\ProgramData\NOX\tor\tor.log` |

Папку с ключом onion-адреса берегут: без неё onion-адрес меняется. Бэкап сервера (`noxd backup`) её не несёт.

## Вручную

### Настройки tor

Onion-сервис NOX — пять строк в настройках tor:

```text
# folder with the onion address's key; tor writes the address to "hostname" in it
HiddenServiceDir /var/lib/tor/nox/
# port 443 of the onion address leads to the NOX server on this machine, over loopback
HiddenServicePort 443 127.0.0.1:8443
# proof of work against floods of requests
HiddenServicePoWDefensesEnabled 1
# at most 16 streams on one circuit; a circuit that opens more is closed
HiddenServiceMaxStreams 16
HiddenServiceMaxStreamsCloseCircuit 1
```

- **Порт 443 ведёт на loopback** — `127.0.0.1:<порт сервера>`: соединения через Tor приходят к серверу оттуда. Поэтому сервер слушает так, чтобы loopback до него доходил, — на всех адресах (`-addr 0.0.0.0:<порт>`, так ставит скрипт) или на самом loopback.
- **Не больше 16 потоков на цепочку.** Onion-адрес открыт любому, кто его знает, а PoW ограничивает только новые подключения к onion-сервису, а не потоки внутри уже открытой цепочки. Устройству хватает одного потока на сокет и нескольких на передачу файлов; цепочку, по которой открыли больше, tor закрывает — чужак не накопит молчащие потоки на одной оплаченной цепочке.
- Нужен tor 0.4.9 или новее, собранный с PoW: `tor --list-modules` показывает `pow: yes`. Сборка без PoW такие настройки отвергает и не стартует.

Отдельному tor, который служит только NOX, добавляют `SocksPort 0`. Скрипт пишет эти строки в отдельный файл (`nox-tor.conf`) и подключает его строкой `%include` — остальные настройки tor не меняются.

Onion-адрес tor пишет в файл `hostname` в папке ключа. Сервер получает его параметром запуска `-onion-addr <адрес>.onion` или кнопкой `Set` на служебной странице.

### Linux

1. tor: `apt install tor` или `dnf install tor`; если в дистрибутиве tor старее 0.4.9 — репозиторий Tor Project по инструкции support.torproject.org. Ключ репозитория сверяют по отпечатку, и в файле не должно быть других ключей: apt и rpm доверяют каждому ключу файла. Для dnf ключ кладут локальным файлом (`/etc/pki/rpm-gpg/RPM-GPG-KEY-torproject`) и пишут `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-torproject` — по адресу `https://` `dnf -y` примет любой ключ, который там окажется. Строки выше — в `/etc/tor/torrc`, затем `systemctl restart tor`.
2. Сервер: `CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /usr/local/bin/noxd .` в `client_backend/`; учётная запись `useradd --system --user-group --no-create-home nox`; папка `/var/lib/nox` (владелец `nox`, права 700); служба — `deploy/noxd.service.tmpl` с подставленными значениями в `/etc/systemd/system/noxd.service`, затем `systemctl enable --now noxd`.
3. Пароль и первое устройство: `noxd unlock`, затем `noxd link -qr`.

### macOS

1. tor: Tor Expert Bundle с dist.torproject.org — архив под свою архитектуру, его подпись или подписанный список сумм `sha256sums-signed-build.txt` проверяются `gpg`. tor из архива на Apple Silicon подписывают ad hoc — `codesign -s - tor libevent-*.dylib`, иначе система убивает его при запуске. Homebrew собирает tor без PoW. Настройки — свой `torrc` (`SocksPort 0`, `DataDirectory`, строки выше), служба — `deploy/com.cyphernetlabs.nox-tor.plist.tmpl`.
2. Сервер: бинарник в `/usr/local/bin/noxd`; служба — `deploy/com.cyphernetlabs.noxd.plist.tmpl` в `/Library/LaunchDaemons/` (владелец `root:wheel`, права 644), затем `sudo launchctl bootstrap system <plist>`.
3. Пароль и первое устройство: `noxd unlock`, затем `noxd link -qr`.

macOS показывает уведомление о новом фоновом объекте — это службы NOX; отключать их в «Объектах входа» не нужно.

### Windows

1. tor: Tor Expert Bundle с dist.torproject.org, проверка подписи — Gpg4win. `tor.exe` с библиотеками рядом — в `C:\Program Files\NOX\tor\`: учётная запись службы не читает папки владельца (рабочий стол, загрузки). Настройки — свой `torrc` (`SocksPort 0`, `DataDirectory`, строки выше; путь к журналу tor — без пробелов). Служба — `--nt-service` первым параметром:

   ```powershell
   New-Service -Name nox-tor -StartupType Automatic `
     -BinaryPathName '"C:\Program Files\NOX\tor\tor.exe" --nt-service -f "C:\ProgramData\NOX\tor\torrc"'
   ```

2. Сервер: `noxd.exe` в `C:\Program Files\NOX\`; служба `noxd` — так же, с командной строкой `"C:\Program Files\NOX\noxd.exe" -addr 0.0.0.0:8443 -db C:\ProgramData\NOX\nox.db -status-addr 127.0.0.1:8081`. Запущенный службой Windows, сервер пишет журнал в `noxd.log` рядом с базой. Учётные записи служб — `sc.exe config <служба> obj= "NT SERVICE\<служба>"`, папки данных — только им, SYSTEM и администраторам; входящие соединения на порт сервера разрешает правило брандмауэра.
3. Пароль и первое устройство: `noxd.exe unlock`, затем `noxd.exe link -qr`.

## Если что-то не так

| Симптом | Что делать |
|---|---|
| `port 8443 is in use by …` | Порт занят другой программой: `--port` с другим портом |
| `port 443 is below 1024 …` | Учётная запись сервера не может слушать этот порт: порт от 1024 (по умолчанию 8443), а 443 — пробросом на роутере |
| `… repository key file is not the Tor Project's key … and nothing else` | Файл ключа репозитория Tor Project пришёл с чужим или лишним ключом — подмена по дороге или на сервере. tor не ставится, сервер ставится без него. Повторить позже; повторится — поставить tor вручную, сверив отпечаток |
| `tor: there is no gpg …` | Поставить gpg (macOS — `brew install gnupg`, Windows — Gpg4win) и запустить скрипт ещё раз: сервер обновится, tor добавится |
| `tor: … is version 0.4.8…` | tor старее 0.4.9 — сеть Tor его не принимает. На Linux скрипт ставит tor из репозитория Tor Project; если не вышло — поставить вручную и запустить скрипт ещё раз |
| `tor did not write its onion address …` | Скрипт показывает конец журнала tor. Чаще всего — права на папку данных tor или чужой tor, занявший её |
| Телефоны в домашней сети не подключаются | Брандмауэр закрыл порт сервера: скрипт подсказывает команду (ufw, firewalld, брандмауэр macOS); на Windows правило ставит сам скрипт |
| Устройства не подключаются после перезагрузки | Сервер заперт: пароль на служебной странице или `noxd unlock` |
| `noxd unlock` пишет `no server answered on …` | Служба не запущена или служебная страница на другом порту: `-status-addr 127.0.0.1:<порт>` |
