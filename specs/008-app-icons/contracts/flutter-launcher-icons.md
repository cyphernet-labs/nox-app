# Contract: flutter_launcher_icons (регенерация, hybrid — не запускается)

Воспроизводимый путь регенерации под будущий вектор (FR-008). В этой фиче конфиг **коммитится, но не запускается** (drop-in crafted-набора имеет приоритет по точности — R1/R7).

## pubspec.yaml

```yaml
dev_dependencies:
  # ... существующие ...
  flutter_launcher_icons: ^0.14.4   # точную версию зафиксировать на этапе implement (latest стабильная, совместимая с FVM 3.44.1)

flutter_launcher_icons:
  image_path: "docs/design/system/nox-app-icons/source/icon-master-1024.png"
  android: true
  ios: true
  macos:
    generate: true
  windows:
    generate: true
  adaptive_icon_background: "#151919"
  adaptive_icon_foreground: "docs/design/system/nox-app-icons/source/icon-foreground-1024.png"
  remove_alpha_ios: true
```

## Контрактные условия

- **Источник** — `docs/design/system/nox-app-icons/source/` (мастер не дублируется в дерево проекта).
- **Запуск (только в будущем, при появлении вектора)**: `fvm dart run flutter_launcher_icons`.
- **Точная версия пакета** проверяется на этапе implement (`mockito`-подобных конфликтов аналайзера здесь нет, но версию пинуем под Dart `>=3.12`).

## Caveats (обязательно к сведению на будущее)

1. **Перезапись**: запуск генератора **перетрёт** drop-in наборы iOS/Android/macOS/Windows выводом генератора — другая трактовка (macOS rounded-rect/margin, Android safe-zone) принимается **вместе с вектором**, не сейчас.
2. **Linux не поддерживается** пакетом — ручной шаг (`linux/packaging/`) остаётся при любой регенерации.
3. **Фон**: при приходе прозрачного вектора сменить `adaptive_icon_background` на бренд `#0C2424` (и `values/ic_launcher_background.xml`).
4. **Web** — `generate` не включаем (вне scope проекта).
