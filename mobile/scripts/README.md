# mobile/scripts — сборка нативных артефактов

## build-libbox.sh

Собирает `libbox.aar` из upstream [SagerNet/sing-box](https://github.com/SagerNet/sing-box) через `gomobile bind`.

Upstream **не публикует** готовый AAR в GitHub Releases — только этот скрипт (или ручная сборка по wiki).

### Требования

| Компонент | Версия |
|---|---|
| Go | 1.24+ (sing-box v1.13.14 go.mod) |
| JDK | OpenJDK 17 |
| Android NDK | 28.0.13004108 (pinned in upstream sdk.go) |
| gomobile | sagernet fork v0.1.12 (`go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12`) |
| Env vars | `ANDROID_HOME`, `JAVA_HOME` |

Подробная инструкция: `wiki/operations/build-libbox-aar.md`

### Быстрый старт (Linux / WSL / macOS)

```bash
# Проверка окружения
go version
java --version          # OpenJDK 17
echo "$ANDROID_HOME"
echo "$JAVA_HOME"
$(go env GOPATH)/bin/gomobile version

# Сборка (~10-20 мин первый раз)
cd mobile
bash scripts/build-libbox.sh

# Результат
ls -la android/app/libs/libbox.aar
unzip -l android/app/libs/libbox.aar | grep libbox.so
```

### Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SINGBOX_VERSION` | `1.13.14` | Тег sing-box для сборки |
| `WORKDIR` | `/tmp/sing-box-build-1.13.14` | Клон upstream (кеш между запусками) |
| `SKIP_BUILD` | `0` | `1` — пропустить gomobile, только скопировать существующий AAR из WORKDIR |
| `SINGBOX_REPO` | `https://github.com/SagerNet/sing-box.git` | URL репозитория |

### После сборки (Commit 2 эпика)

```bash
sha256sum android/app/libs/libbox.aar
git add -f android/app/libs/libbox.aar
git commit -m "build(mobile): pre-built libbox.aar v1.13.14"
```

### Troubleshooting

- **`package github.com/sagernet/sing-tun: not found`** — подмодули не инициализированы. Скрипт делает `git submodule update --init --recursive` автоматически; если упало — удалите `WORKDIR` и запустите снова.
- **`flag provided but not defined: -libname`** — установлен google gomobile вместо sagernet fork. Используй `github.com/sagernet/gomobile/cmd/gomobile@v0.1.12`
- **`gomobile: command not found`** — скрипт установит sagernet/gomobile автоматически, или вручную: `go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12 && go install github.com/sagernet/gomobile/cmd/gobind@v0.1.12 && gomobile init`
- **`java version should be openjdk 17`** — upstream жёстко требует JDK 17 (см. `cmd/internal/build_libbox/main.go`)
- **Нет `armeabi-v7a/libbox.so`** — известная проблема gomobile для 32-bit. Для MVP достаточно `arm64-v8a`; armv7 остаётся на CLI fallback до отдельной итерации.

### Проверка синтаксиса скрипта

```bash
bash -n mobile/scripts/build-libbox.sh
```
