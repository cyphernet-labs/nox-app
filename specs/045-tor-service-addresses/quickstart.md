# Quickstart: проверка Tor отдельной службой

## 1. Автоматические проверки

```bash
make tor-test                                              # модуль без ключей доступа, сборка с hs-pow-full
cd client_backend && gofmt -l . && go vet ./... && go test -race ./...   # адреса, параметры, форма Set, ссылки, нет tor
make gate && make golden-verify                            # настройки связи, селектор, причины, экраны обеих ширин
```

## 2. Сквозной прогон на macOS

tor — сборка Tor Project (`tor` 0.4.9+), отдельно от сервера:

```bash
# Сервер с новой базой и адресами в параметрах
cd client_backend && go build -o "$STAND/noxd" . && \
  "$STAND/noxd" -db "$STAND/nox.db" -addr 0.0.0.0:8443 -status-addr 127.0.0.1:8081

# tor со своим onion-сервисом на порт сервера (torrc):
#   SocksPort 0
#   HiddenServiceDir $STAND/hs
#   HiddenServicePort 443 127.0.0.1:8443
#   HiddenServicePoWDefensesEnabled 1
tor -f "$STAND/torrc"
# onion-адрес — в $STAND/hs/hostname
```

1. На служебной странице `http://127.0.0.1:8081` задать onion-адрес кнопкой `Set` → он в новом QR-коде; задать испорченный → `That isn't a valid onion address.`, ничего не изменилось.
2. Перезапустить сервер с `-onion-addr <тот же адрес>` → правка со страницы на месте; с испорченным `-onion-addr` → сервер работает, на странице предупреждение.
3. Приложение (`fvm flutter run -d macos --dart-define-from-file=config/stage.json`): вставить ссылку → экран подключения с адресами из ссылки, `Use Tor` выключен → `Connect` → спарено напрямую.
4. В «Связи» вписать недоступный адрес сервера, `Save` → баннер `Can't reach the server directly. Turn on Use Tor to connect through Tor.`
5. Включить `Use Tor` → связь через Tor (угол `Tor`), сообщение доходит один раз.
6. Вернуть верный адрес → приложение уходит на прямой путь не позже чем через 2 минуты.
7. Остановить tor → `No server answers at this onion address…` или `Your server isn't answering through Tor right now…` (по виду ошибки Arti).
8. Новое устройство: спарить по ссылке с onion-адресом через Tor, прямой адрес недоступен.

## 3. Проверки владельца

- Windows и Linux (Tor на Linux теперь включён): сборка, `Use Tor`, связь через Tor.
- iOS и Android на устройстве: связь через Tor, время решения PoW на iOS.
