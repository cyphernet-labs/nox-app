# Контракт: модуль `nox_tor` без ключей доступа (дельта к 044)

## Уходит

- `int32_t nox_tor_set_target(const char *onion_host, uint16_t port, const uint8_t *client_key32)`
- `int32_t nox_tor_clear_target(void)`
- В Dart — `NoxTor.setTarget`, `NoxTor.clearTarget` и всё, что держит ключ доступа.

Канал к onion (`nox_chan_open`, `target_kind = 1`) идёт через клиента Arti по адресу — цель заранее не задаётся. Подстраховочное подключение запоминает выигравшую группу изоляции для каждого onion-сервиса отдельно.

## Без изменений

`nox_tor_start`, `nox_tor_stop`, `nox_tor_set_dormant`, `nox_tor_status` (раскладка `NoxTorStatus` та же; коды `MISSING_CLIENT_AUTH`, `WRONG_CLIENT_AUTH` остаются в нумерации и не возникают), `nox_tor_onion_from_pubkey`, `nox_tor_version`, весь `nox_chan_*`.

## Сборка

`arti-client =0.47.0` с фичей `hs-pow-full`; фичи `keymgr`, `ephemeral-keystore` и зависимость `tor-keymgr` уходят, если ничего другого им не нужно. Версии Arti — точные (`=`), смена версии — отдельное решение с проверкой PoW.
