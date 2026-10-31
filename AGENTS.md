# AGENTS.md — Proxy Dom

> Правила для ИИ-агентов (Cursor, Claude Code, Codex и любые другие).
> Читается на старте сессии. Язык: owner — по-русски, код, коммиты и PR —
> по-английски.

**Это клиентский репозиторий.** Бэкенда, Terraform, сайта и внутренних
ops-документов здесь нет: они остались в закрытом репозитории. Всё, что есть, —
это Flutter-приложение и Go-движок, из которых собирается APK, XCFramework и
`proxydom-engine.exe`.

---

## 0. Команды

Те же, что гоняет CI (`.github/workflows/mobile-build.yml`):

```bash
cd mobile && flutter pub get
flutter analyze --no-fatal-infos
flutter test --dart-define=AUTH_ANONYMOUS=false
flutter test test/dial_set_test.dart          # один файл

cd android/hysteria-bind
go mod tidy -diff                             # go.mod — единственный пин версий
go test ./...
go test -run TestLicenseGuard .               # один тест
GOOS=windows GOARCH=amd64 go build ./... && GOOS=windows GOARCH=amd64 go vet ./...
```

Kotlin-тесты (`./gradlew :app:testDebugUnitTest` в `mobile/android`) требуют
собранного `hysteria-client.aar` — см. `mobile/AGENTS.md`.

## 1. Имена

| Что | Значение |
|---|---|
| Приложение, ru / en | **Прокси Дом** / **Proxy Dom** |
| Google Play | `com.proxy.dom` |
| Android namespace | `com.proxydom.app` |
| Bundle id iOS | `su.proxydom.app` |
| Расширение iOS | `su.proxydom.app.VpnTunnelProvider` |
| App Group iOS | `group.su.proxydom.app` |
| Dart-пакет | `proxydom` |
| Windows-служба | `ProxyDomBroker`, движок `proxydom-engine.exe` |

## 2. Продукт

**Локальный конфигуратор.** Человек вставляет ключ или документ подписки и
выбирает строку. Приложение не ведёт аккаунт, не продаёт доступ, не выдаёт
документы и **не отправляет учётные данные узлов на сервер**.

Приложение бесплатное на всех платформах, денег в нём нет вообще. Это важно для
§6: лицензионные ограничения клиента касаются не выручки, а самого факта
распространения, поэтому «приложение бесплатное» их не снимает.

**Что клиент умеет запускать** (подробно и по платформам решает только код,
документация это не дублирует):

- **Hysteria2** — `hy2://` и `hysteria2://`, включая `obfs=salamander`, на
  всех ОС. Port hopping движок умеет (`hy2bind_hop.go`), но сейчас его несёт
  только Windows-брокер: Android и iOS не передают `server_ports`, а диапазон
  прямо в порту (`host:20000-30000`) Dart-парсер отбрасывает на всех ОС.
- **Импорт** — Hysteria2 на всех ОС и вся семья `v2fly/v2ray-core` там, где
  движок её набирает: Android, Windows и iOS. Это VLESS, VMess, Trojan,
  Shadowsocks и SOCKS5. Основной движок — in-process `v2fly/v2ray-core`
  v5.54.2 (MIT) внутри `hy2bind`; на Windows тот же исходник становится
  `proxydom-engine.exe`, на iOS семья идёт через packet-flow dataplane.
  **Reality** несёт отдельный permissive-движок в `hy2bind/share_reality.go`
  (uTLS + VLESS, без `xray-core`): TCP и UDP. XTLS Vision в нём пока нет, такие
  Reality-строки остаются неактивными. **XHTTP** тоже не несёт ни один движок.

`wireguard://`, `amneziawg://` и `vpn://` парсер опознаёт, считает и называет,
но не запускает: в `hy2bind` нет userspace-WireGuard, а `vpn://` — контейнер, а
не диалер. Смешанный документ импортируется целиком и не удаляется; строки,
которые платформа не умеет запустить, показываются с нейтральным бейджем, а не
с ошибкой. Источник правды — `mobile/lib/features/vpn/data/dial_set.dart`.
Разбор INCY, из которого этот набор вырос, — `docs/parity/incy-intake-parity.md`.

## 3. Стек

- **UI:** Flutter + Riverpod + go_router, MethodChannel `proxydom/vpn`
- **Движок:** Go, `mobile/android/hysteria-bind/` — `v2fly/v2ray-core` v5.54.2
  (MIT) + `tun2socks`. Android — gomobile-архив, iOS — XCFramework, Windows —
  `proxydom-engine.exe`
- **Android:** `minSdk = 26` жёстко (`requiredMinSdk`), `VpnService`
- **iOS:** Packet Tunnel Provider, iOS 15+
- **Windows:** C++ TUN-служба + MSI
- **CI:** GitHub Actions

```
mobile/     Flutter-приложение (lib/, test/, android/, ios/, windows/)
desktop/    Windows: service/ (C++) + installer/ (MSI)
.github/    CI: mobile-build (PR), ios-compile (PR), windows-service (PR),
            android-apk и ios-testflight (вручную)
```

## 4. Стиль

**Dart:** `flutter analyze` без новых замечаний; никаких `Color(0xFF…)` в
виджетах — только `AppBrand` / `ColorScheme`; строки — через `mobile/lib/l10n/`,
не хардкодить.

**Go:** обычный `gofmt`; комментарии объясняют «почему», не «что».

**Тесты** проверяют поведение, а не галочку. Тест, который проходит на сломанной
реализации, хуже отсутствующего: он заявляет покрытие, которого нет. Тесты
вызывают код, а не читают исходники как текст: grep по `lib/`, `main.go` или
чужому языку ломается от переименования и не ловит регрессию. Правило, которое
нельзя проверить поведением, живёт в этом файле и в ревью, а не в тесте.

**Комментарии и документы** не ссылаются на ADR, номера задач и прошлые решения:
причина пишется рядом с кодом, которым она управляет.

## 5. CI ≠ устройство

Набор команд в CI совпадает с §0. Джоба `hy2bind-aar` собирает
`hysteria-client.aar` через gomobile и отдаёт его Android-джобам артефактом:
ей нужны Go и NDK раннера, поэтому красное на этом шаге — не Kotlin. Внутри
потребителя архив не собирается — Go-кеш и четыре ABI на той же машине, что
пакует APK, упираются в диск.

**Зелёный CI не равен работающей сборке.** Android и iOS проверяются на живом
устройстве, Windows — на живой сессии из локального MSI. Не выдавать «должно
работать» за «проверено».

## 6. Границы

Внешние ограничения, а не договорённости:

- **GPL-3.0 и AGPL-3.0 в клиентской сборке — нельзя.** Не «нежелательно»:
  §10 запрещает накладывать дополнительные ограничения на предоставленные
  права, а §12 при несовместимости обязательств запрещает распространять
  произведение вообще. Условия App Store (DRM, подпись кода, лимит устройств) —
  ровно такое ограничение. Конфликт про распространение, а не про цену, поэтому
  бесплатность приложения его не снимает. Клиент собирается только из
  permissive: MIT, BSD, ISC, Apache-2.0, MPL-2.0. Это не «без обязательств»:
  MIT, BSD и Apache требуют сохранить копирайт-нотисы, и они лежат в
  `mobile/assets/legal/THIRD-PARTY-NOTICES.md`.
- **`libbox`, `sing-box` не вендорить.** Внутри GPL-3.0, см. пункт выше.
- **`xray-core` не вендорить, и это проверено на практике.** Сам пакет —
  MPL-2.0 (в его `LICENSE`), но его сборочный граф тянет GPL-3.0 и LGPL:
  `sagernet/sing` приходит из `transport/internet` (импорт
  `sing/common/control` в `system_dialer.go`), `sagernet/sing-shadowsocks` —
  из `infra/conf`, `juju/ratelimit` (LGPL) — через `xtls/reality`. Проверено
  2026-10-30 командой `go mod why` на v1.260327.0; `TestLicenseGuard` валит
  такую сборку. Поэтому `xray-core` в клиент не входит. Reality этого не
  требует: её клиентская половина реализована отдельно в
  `hy2bind/share_reality.go` на uTLS, без графа Xray. XHTTP по-прежнему не
  несёт ни один движок; его фрейминг придётся реализовать так же отдельно.
  Переход на сам `xray-core` возможен лишь если GPL/LGPL-части будут вырезаны
  из графа (форк или build-теги), а это отдельное решение.
- **`com.android.vending.BILLING` не добавлять.** Платежей в приложении нет.
- **Секреты и ключи серверов не отправлять на сервер.** Утилита локальная.

## 7. Рабочий процесс

- **Один агент — одно рабочее дерево.** Параллельная задача идёт в своём
  `git worktree` на своей ветке, а не в общей папке: два агента в одном дереве
  перетирают файлы друг друга и коммитят чужие правки.
- Ветка от `main`: `feat/…`, `fix/…`, `docs/…`, `refactor/…`, `chore/…`.
  Conventional Commits; один коммит — одно откатываемое поведение, дерево
  собирается и тесты зелёные на каждом.
- В коммит идут только свои файлы (`git add <path>`, не `-A`): в дереве может
  лежать чужая незаконченная работа.
- Перед сдачей — команды из §0. Красный тест чинится или явно называется в
  отчёте; «должно работать» не выдаётся за «проверено» (§5).
- Продукты сборки (`*.aar`, `*.xcframework`, APK, MSI, логи, скриншоты) не
  коммитятся.

## 8. Чего в этом репозитории нет

Не искать и не добавлять: бэкенда FastAPI, Terraform, Ansible, лендинга,
каталога узлов, Telegram-бота, биллинга, wiki. Всё это живёт в закрытом
репозитории. Если задача требует правку бэкенда — она не для этого репозитория.
