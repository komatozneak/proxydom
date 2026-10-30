# Паритет приёма ключей с INCY: что разобрано и что сделано

> Собрано 2026-10-30 по бинарнику INCY 3.8.1 (`llc.itdev.incy`), разобранному
> **REA 6.8.0** (движок JADX 0.7.1). Ничего из INCY в сборку не переносилось:
> разбирали форматы приёма и список транспортов, реализация — своя.

## 0. Артефакты разбора

| Что | Где | Отпечаток |
|---|---|---|
| Android APK 3.8.1 | `.scratch/ref/bin/Incy.apk` (gitignore) | `sha256:67c8253b3dc5fd2a0a0b27d5d4736834fa43e276a1a54d3282f5df0935092836` |
| Windows portable 3.9.0 | `.scratch/ref/bin/incy-win/` | `/app/incy-desktop-3.9.0.jar` (Kotlin/Compose, jpackage) |
| Декомпиляция | `.scratch/ref/jadx-out/sources/` | 11 105 `.java` |

Воспроизвести:

```powershell
# 1. REA: инвентарь и список классов
$env:REA_JADX_MCP_JAR = "$HOME\.local\share\rea\android\jadx-headless-mcp-0.7.1-all.jar"
rea inspect-android-package <Incy.apk> --json
rea search-android-classes <Incy.apk> . --json      # все классы
rea inspect-android-class <Incy.apk> <класс>        # один класс целиком

# 2. JADX: массовая декомпиляция (тот же движок, что пининит REA)
java -cp "jadx\lib\*" jadx.cli.JadxCLI --no-res -d jadx-out Incy.apk
```

Приложение обфусцировано R8 (90% классов — `a1.a0`, `wg.a`), но строки и
SQL-схема целы, и парсер опознаётся по строковым литералам.

## 1. Что INCY принимает на вход

Один диспетчер — `pg/f.java`, метод `h(String, String)`. Схема попадает в него
из трёх мест: поля вставки, сканера QR (`bh/y2.java`) и `intent-filter`
манифеста.

| Вход | Разбор | Что внутри |
|---|---|---|
| `vless://` | `v()` | uuid, `security` (`tls`/`reality`/`none`), `pbk`/`sid`/`spx`, `flow`, `type` (tcp/ws/grpc/httpupgrade/xhttp/kcp/quic), `sni`, `fp`, `alpn`, `path`, `host`, `headerType`, `ech`, `pinnedPeerCertSha256` |
| `vmess://` | `x()` | base64 JSON: `add`,`port`,`id`,`net`,`tls`,`sni`,`host`,`path`,`scy`,`alpn`,`ps` |
| `trojan://` | `s()` | пароль, `security`, `type`, `sni`, `fp`, `path`, `host` |
| `ss://` | `p()` | SIP002 и legacy-base64, `method`+`password`, плагины |
| `hysteria2://`, `hy2://` | `m()` | userpass, `obfs=salamander`, `obfs-password`, `mport` + `mportHopInt`, `fm` (QUIC-параметры) |
| `socks5://`, `socks://` | `r()` | user/pass, host:port |
| `wireguard://`, `wg://` | `z()` | URI → WireGuard INI (`[Interface]`/`[Peer]`), включая Amnezia-поля `Jc/Jmin/Jmax/Itime` |
| `amneziawg://`, `awg://` | `h()` | base64 INI AmneziaWG |
| `vpn://` | `h()` | base64-документ: JSON-конфиг Xray, INI или список share-ссылок |
| `http://` с `@` | `l()` | HTTP-прокси: user:pass@host:port |
| WireGuard INI целиком | `A()` | `[Interface]` + `PrivateKey` → сервер |
| Полный JSON Xray | `B()` | `{"inbounds":…,"outbounds":…}` сохраняется как `fullConfigJson` |
| Подписка | — | base64 или plain-список строк; заголовки `subscription-userinfo`, `profile-title`; `SubscriptionRefreshWorker` обновляет по расписанию |

Классификатор типа входа — `wg/a.java`: отдельно опознаются подписка,
routing-профиль, share-ссылка, «несколько ссылок в тексте», WireGuard INI,
JSON-конфиг.

Глубокие ссылки в манифесте INCY: `incy`, `vless`, `vmess`, `trojan`, `ss`,
`awg`, `amneziawg`, `vpn` — «Открыть в INCY» работает прямо из чужого
приложения.

Схема БД `servers` перечисляет всё, что клиент умеет хранить: `xhttpMode/
xhttpExtra`, `publicKey/shortId/spiderX` (Reality), `hy2Obfs*`, `portHopping*`,
`wg*`, `amneziaConfText`, `sstpSni/sstpDns/sstpCaCert`, `oc*` (OpenConnect),
`olcrtc*`, `noises`, `finalmask`, `echConfigList`, `mldsa65Verify`,
`fullConfigJson`. Go-биндинги `incycore.*` (`SSTPStats`,
`OpenConnectTunnelInfo`, `AmneziaWGStats`) подтверждают, что SSTP, OpenConnect и
AmneziaWG действительно запускаются.

## 2. Что из этого теперь умеет «Прокси Дом»

### 2.1 Приём ключей

| Формат | Было | Стало |
|---|---|---|
| `hysteria2://`, `hy2://` | да | да |
| `vless://`, `vmess://`, `trojan://`, `ss://` | разбирались и лежали «в парке» | разбираются и **запускаются** на Android/Windows |
| `socks5://`, `socks://` | не опознавались (строка исчезала) | разбираются и **запускаются** на Android/Windows |
| `wireguard://`, `wg://`, `amneziawg://`, `awg://`, `vpn://` | не опознавались (строка исчезала) | опознаются и **считаются**: строка получает нейтральный бейдж и причину, документ не теряет ключи |
| `http://user:pass@host` | — | сознательно **не** ключ: этот же вид у адреса подписки, до запроса их не различить (см. §3) |
| Deep links из чужого приложения | только `proxydom://add/…` | `hysteria2`, `hy2`, `vless`, `vmess`, `trojan`, `ss`, `socks5` — `intent-filter` в манифесте Android |
| QR | да | да (список схем расширен вместе с парсером) |

Ключевое изменение поведения: раньше строка с неизвестной схемой просто
пропускалась — документ из трёх ключей выглядел как документ из одного, и
человек не знал, что потерял два. Теперь такие строки попадают в
«не поддержано N» с названием протокола.

### 2.2 Методы подключения

Движок один на оба настольных и мобильных пути: `v2fly/v2ray-core` v5.54.2
(MIT) внутри `hy2bind`. Hysteria2 — отдельный диалер того же `hy2bind`.

| Протокол | Android | Windows | iOS |
|---|---|---|---|
| Hysteria2 (+obfs, port hop) | да | да | да |
| VLESS (tcp/ws/kcp × tls/none, uTLS) | да | да | нет |
| VLESS поверх gRPC и HTTPUpgrade | да | да | нет |
| VMess (tcp/ws/kcp × tls/none) | да | да | нет |
| Trojan | да | да | нет |
| Shadowsocks (AEAD) | да | да | нет |
| SOCKS5 (с авторизацией и без) | да | да | нет |
| Reality, XHTTP, QUIC | нет | нет | нет |

Reality и XHTTP по-прежнему не запускаются: `v2ray-core` их не описывает, и
`buildShareSocksConfig` возвращает `null` — строка остаётся неактивной с
нейтральным бейджем, а не падает на старте.

### 2.3 Где правки

| Слой | Файл | Что |
|---|---|---|
| Парсер | `mobile/lib/features/vpn/data/share_link_parser.dart` | схемы `socks5`/`socks` разбираются, `wireguard`/`amneziawg`/`vpn` опознаются и отклоняются по имени |
| Гейт | `mobile/lib/features/vpn/data/dial_set.dart` | `_v2raySchemes`, `kParkedSchemes` — единственное место, решающее, что запускается |
| Документ | `mobile/lib/features/vpn/data/engine_share_config.dart` | `_socks()`, `grpcSettings`, `httpupgradeSettings` |
| Старт | `mobile/lib/features/vpn/data/vpn_controller.dart` | `outboundType` = настоящая схема (для подписи в UI) |
| Вызов | `mobile/lib/features/home/application/vpn_provider.dart` | передаёт схему в старт |
| Go-загрузчик | `mobile/android/hysteria-bind/hy2bind_engine_load.go` | outbound `socks`, транспорты `grpc` и `httpupgrade` |
| Windows-движок | `mobile/android/hysteria-bind/cmd/proxydom-engine/config.go` | `engineShare` вместо `engineVLESS`, `shareOutbound()` на все пять, `grpcSettings`/`httpupgradeSettings` |
| Windows-брокер | `desktop/windows/service/protocol.cpp/.h` | разбор vmess (base64 JSON), ss (SIP002 + legacy), trojan, socks5, `serviceName`; `engine_outbound` на все пять |
| Вход из ОС | `mobile/android/app/src/main/AndroidManifest.xml`, `mobile/lib/app.dart` | intent-filter на схемы ключей и приём голой ссылки в импорте |
| Логи | `mobile/lib/core/diagnostics/tunnel_log_redact.dart` | `socks5`/`socks` в маске userinfo |

## 3. Осознанные расхождения

1. **`http://user:pass@host` не считается ключом.** У INCY это HTTP-прокси; у
   нас `http(s)://` — адрес документа подписки, и различить их можно только
   после запроса. Приём ключа ценой сломанного приёма подписки — плохой обмен.
2. **`wireguard://`, `amneziawg://`, `vpn://` не запускаются.** В `hy2bind` нет
   userspace-WireGuard (это `wireguard-go` + netstack, отдельная работа и
   отдельный вес бинарника), `vpn://` — контейнер, а не диалер.
3. **Reality и XHTTP не запускаются.** Их умеет `XTLS/Xray-core`; его
   `LICENSE` — MPL-2.0, то есть лицензионно он допустим (клиент собирается из
   MIT/BSD/ISC/Apache-2.0/MPL-2.0). Движок сейчас другой — `v2fly/v2ray-core`,
   и переход на `xray-core` это архитектурная работа, а не правка парсера.
4. **SSTP, OpenConnect, OlcRTC, «noises»** у INCY живут в его Go-ядре
   (`incycore.*`); у нас нет ни одного из этих транспортов, и они не входят в
   список протоколов из README INCY, поэтому в паритет не заявлены.
5. **Локальный HTTP/SOCKS5-прокси без туннеля** у нас отсутствует: это режим
   работы, а не формат ключа.
6. **Полный JSON Xray** как импорт конфигурации не принимается: загрузчик
   `hy2bind` описывает только пять outbound'ов из §2.2 и транспорты
   `tcp/ws/kcp`.

## 4. Проверка

```powershell
cd mobile
flutter analyze --no-fatal-infos                     # без новых замечаний
flutter test --dart-define=AUTH_ANONYMOUS=false      # dial_set, share_link_parser, engine_share_config

cd ..\mobile\android\hysteria-bind
go test ./...                                        # AAR проверяется отдельно, см. §5

cd ..\..\desktop\windows\service
cmake -S . -B build-check -G Ninja
cmake --build build-check --target protocol_test supervisor_test share_config
.\build-check\protocol_test.exe                      # -> ok
.\build-check\supervisor_test.exe                    # -> ok
```

Тесты фиксируют поведение: `dial_set_test.dart` перечисляет, что запускается на
каждой ОС; `protocol_test.cpp` проверяет, что vmess/ss/trojan/socks5 дают тот же
документ, что строит Dart; `config_test.go` — что движок Windows собирает из
него outbound и не выдумывает транспорт у SOCKS5.

### 4.1 Живая проверка на тестовом сервере

Стенд: `31.59.170.81` (Ubuntu 24.04), Xray 26.3.27, по инбаунду на протокол,
самоподписанный сертификат `CN=31.59.170.81`. Проверка идёт двумя независимыми
путями: ПК гоняет реальный `proxydom-engine.exe` в режиме loopback-прокси и
обязан получить `https://ifconfig.me/ip` равным адресу стенда, телефон
(Pixel 7 Pro, Android 17) получает ключ deep link'ом, поднимает туннель и пишет
собственный `vpn.egress_probe ok=true … external_ip=<адрес стенда>`.

| Случай | Порт | ПК | Android |
|---|---|---|---|
| VLESS + TLS (tcp) | 8443 | PASS | PASS |
| VLESS + TLS (ws, `/ws`) | 8444 | PASS | PASS |
| Trojan + TLS | 8445 | PASS | PASS |
| VMess + TLS | 8446 | PASS | PASS |
| Shadowsocks (chacha20-ietf-poly1305) | 8447 | PASS | PASS |
| SOCKS5 с логином/паролем | 1080 | PASS | PASS |
| VLESS + TLS поверх gRPC (`serviceName=grpcsvc`) | 8448 | PASS | PASS |
| VLESS + TLS поверх HTTPUpgrade (`/up`) | 8449 | PASS | PASS |

16 из 16: каждый протокол проверен на обеих платформах. Подробный журнал, включая
найденные этой проверкой дефекты клиента, — `docs/parity/verification-log.md`.

### 4.2 UI-правки этой итерации

- Алерт на телефоне больше не садится на нижнюю кнопку действия: он выезжает
  сверху, под статус-бар, и не перехватывает нажатия (`IgnorePointer`), поэтому
  «Сохранить» нельзя случайно накрыть уведомлением.
- `_busy` в экране импорта сбрасывается в `finally`: кнопка не может остаться
  навсегда неактивной после сохранения, которое не привело к навигации.
- Голая ссылка из ОС добавляется сразу, а `vmess://` довозится до парсера
  сырой строкой intent'а: у `Uri` host приводится к нижнему регистру, а в VMess
  в host лежит base64.

## 5. Что осталось для полного паритета

| Что | Почему не здесь | Оценка |
|---|---|---|
| Reality + XHTTP | переход `hy2bind` с `v2fly/v2ray-core` на `XTLS/Xray-core` (MPL-2.0): другой набор пакетов, REALITY и XHTTP только там | большая |
| WireGuard / AmneziaWG | новый outbound: `wireguard-go` (MIT) + netstack (Apache-2.0), ~400–600 строк Go + gomobile | средняя |
| SSTP / OpenConnect | готовых permissive-библиотек на Go нет | большая |
| Полный JSON-импорт | нужен загрузчик, описывающий больше, чем пять outbound'ов | средняя |
| Режим «только прокси» | продуктовый сценарий, не формат | малая |

Переход на `xray-core` проверен и отложен по лицензии, а не по вкусу: его
`LICENSE` — MPL-2.0, но сборочный граф тянет `sagernet/sing` (GPL-3.0) через
`transport/internet`, `sagernet/sing-shadowsocks` (GPL-3.0) через `infra/conf` и
`juju/ratelimit` (LGPL) через `xtls/reality`. Это ловится `go mod why` и валится
`TestLicenseGuard`. Пока эти части не вырезаны из графа, Reality и XHTTP в
клиенте не появятся.
