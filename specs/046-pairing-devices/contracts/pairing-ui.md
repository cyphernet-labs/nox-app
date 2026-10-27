# Контракт: экраны спаривания и запрос `Allow`/`Deny`

Обе ширины, EN + UK.

## Новое устройство — ожидание

| Элемент | EN | UK |
|---|---|---|
| Ожидание | `Waiting for approval on your other device` | `Очікуємо підтвердження на вашому іншому пристрої` |
| Кнопка | `Cancel` | `Скасувати` |
| Отказ | `Your other device declined this request.` | `Ваш інший пристрій відхилив цей запит.` |
| Срок | строка истёкшей ссылки (`loginLinkExpired`) | |

## Выдавшее устройство — диалог поверх любого экрана

| Элемент | EN | UK |
|---|---|---|
| Текст | `New device: {platform}. Allow it to join?` | `Новий пристрій: {platform}. Дозволити йому приєднатися?` |
| Кнопки | `Allow` · `Deny` | `Дозволити` · `Відхилити` |

`{platform}` — `iPhone or iPad` / `Android` / `Mac` / `Windows` / `Linux` (EN), `iPhone або iPad` / `Android` / `Mac` / `Windows` / `Linux` (UK). Диалог закрывается после ответа, отказа нового устройства или срока.

## 7.8 Устройства

Без изменений строк, кроме: подпись `This link works only on your home network.` — когда в ссылке нет ни onion, ни публичного адреса.
