# Quickstart: проверка Tor отдельной службой

## 1. Автоматические проверки

```bash
make tor-test                                              # модуль без ключей доступа, сборка с hs-pow-full
cd client_backend && gofmt -l . && go vet ./... && go test -race ./...   # адреса, параметры, форма Set, ссылки, нет tor, журнал без onion-адресов и ссылок
make gate && make golden-verify                            # настройки связи, селектор, причины, экраны обеих ширин
```

## 2. Сквозной прогон на macOS

tor — сборка Tor Project (`tor` 0.4.9+), отдельно от сервера:

```bash
# Сервер с новой базой; onion-адрес задаётся на странице (п. 1) или параметром -onion-addr
cd client_backend && go build -o "$STAND/noxd" . && \
  "$STAND/noxd" -db "$STAND/nox.db" -addr 0.0.0.0:8443 -status-addr 127.0.0.1:8081

# Сервер стартует запертым (047): до пароля слушает только служебная страница.
# Пароль — на странице или из другого терминала; новый сервер принимает его дважды
"$STAND/noxd" unlock -status-addr 127.0.0.1:8081

# tor со своим onion-сервисом на порт сервера на loopback (torrc):
#   SocksPort 0
#   DataDirectory $STAND/tor-data
#   HiddenServiceDir $STAND/hs
#   HiddenServicePort 443 127.0.0.1:8443
#   HiddenServicePoWDefensesEnabled 1
#   HiddenServiceMaxStreams 16
#   HiddenServiceMaxStreamsCloseCircuit 1
# PoW удорожает только новые цепочки, а не потоки на построенной:
# не больше 16 потоков на цепочку, и цепочка, попросившая больше, закрывается.
tor -f "$STAND/torrc"
# onion-адрес — в $STAND/hs/hostname
```

Ссылка спаривания — на служебной странице, когда пароль введён, или у `noxd link`: журнал сервера говорит, где страница, и не печатает ни ссылку, ни onion-адрес.

1. На служебной странице `http://127.0.0.1:8081` задать onion-адрес кнопкой `Set` → он в новом QR-коде; задать испорченный → `That isn't a valid onion address. Nothing was changed.`, ничего не изменилось.
2. Перезапустить сервер с `-onion-addr <тот же адрес>` → адрес на месте; задать на странице другой и перезапустить с тем же параметром → правка со страницы на месте; с испорченным `-onion-addr` → сервер работает, на странице предупреждение.
3. Приложение (`fvm flutter run -d macos --dart-define-from-file=config/stage.json`): вставить ссылку со страницы → экран подключения с адресами из ссылки, `Use Tor` выключен → `Connect` → спарено напрямую.
4. Уйти из сети сервера — телефон в мобильной сети → баннер `Can't reach the server directly. Turn on Use Tor to connect through Tor.` Недоступный адрес, вписанный в «Связи», баннера не даёт: приложение пробует и остальные известные ему прямые адреса — последний рабочий и найденные сервером. На одной машине «вне дома» делает живая проба (ниже).
5. Включить `Use Tor` → связь через Tor (угол `Tor`), сообщение доходит один раз.
6. Вернуться в сеть сервера → прямой путь сразу при смене сети, иначе не позже чем через 2 минуты.
7. Остановить tor на машине сервера → `Your server isn't answering through Tor right now…`: описание сервиса ещё лежит в каталогах Tor, а его точки входа молчат. Запустить tor и остановить сервер → то же сообщение. `No server answers at this onion address…` — у адреса, который никто не публикует (например, вписанного в «Связи» с ошибкой, но с верной контрольной суммой).
8. Новое устройство: спарить по ссылке с onion-адресом через Tor, прямой адрес недоступен.

Те же шаги без экранов — живые пробы (вручную, вне гейтов; каталог `work` очищается в начале прогона):

```bash
fvm flutter test test/live/tor_live_probe.dart --dart-define=noxd=$STAND/noxd --dart-define=tor=<путь к tor> \
  --dart-define=host=<LAN-адрес машины> --dart-define=work=/tmp/nox_e2e \
  [--dart-define=port=18443] [--dart-define=other_onion=<56>.onion]   # onion-адрес другого сервера - для otherServer
fvm flutter test test/live/tor_pairing_probe.dart \
  --dart-define=link="$("$STAND/noxd" link -status-addr "$(cat /tmp/nox_e2e/page.txt)" | head -1)"
fvm flutter test test/live/resumable_files_probe.dart --dart-define=noxd=... --dart-define=tor=... \
  --dart-define=host=... --dart-define=work=/tmp/nox_files_e2e [--dart-define=mib=100] [--dart-define=port=18543]
```

Пароль своих серверов пробы вводят сами (047). `tor_live_probe` оставляет сервер и его tor работать, а адрес служебной страницы — в `/tmp/nox_e2e/page.txt`. Приглашение спаривает только после `Allow` на выдавшем устройстве (046), поэтому `tor_pairing_probe` и `integration_test/tor_pairing_test.dart` приносят выдавшее устройство с собой: оно спаривается дома по свежей ссылке с машины (ссылка живёт 10 минут), выдаёт приглашение и разрешает запрос, пока приложение спаривается по приглашению через Tor.

## 3. Проверки владельца

- Windows и Linux (Tor на Linux теперь включён): сборка, `Use Tor`, связь через Tor.
- iOS и Android на устройстве: связь через Tor, время решения PoW на iOS.
- Экраны руками на обеих ширинах: экран подключения, «Связь», баннеры с причинами.
