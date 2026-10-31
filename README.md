# Прокси Дом · Proxy Dom

> Клиент для Android, iOS и Windows, который превращает ключ или документ
> подписки в работающее прокси-соединение. Локально, без аккаунта и без оплаты.

[![Mobile build](https://github.com/komatozneak/proxydom/actions/workflows/mobile-build.yml/badge.svg)](https://github.com/komatozneak/proxydom/actions/workflows/mobile-build.yml)
[![Windows Service](https://github.com/komatozneak/proxydom/actions/workflows/windows-service.yml/badge.svg)](https://github.com/komatozneak/proxydom/actions/workflows/windows-service.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Что это

**Прокси Дом** — локальный конфигуратор. Человек вставляет ключ (`hy2://`,
`vless://`, …) или ссылку на документ подписки, выбирает строку — и приложение
поднимает туннель через выбранный сервер.

Приложение **не** ведёт аккаунт, **не** продаёт доступ, **не** выдаёт ключи и
**не** отправляет учётные данные серверов куда-либо. Ключ, который вы вставили,
остаётся на устройстве. Это не сервис и не каталог: это инструмент.

| | |
|---|---|
| **Название** | Прокси Дом / Proxy Dom |
| **Android** | [`com.proxy.dom`](https://play.google.com/store/apps/details?id=com.proxy.dom), minSdk 26 |
| **iOS** | `su.proxydom.app`, iOS 15+ |
| **Windows** | MSI, служба `proxydom-engine.exe` |
| **Цена** | Бесплатно, в приложении нет платежей |
| **Лицензия** | [MIT](LICENSE) |

## Что это не

- **Не сервис доступа.** Приложение не продаёт и не выдаёт доступ. Сервер
  выбираете вы — свой или чужой.
- **Не каталог.** Списка «наших» узлов в открытой сборке нет.
- **Не сервис доступа к сторонним ресурсам.** Продукт — клиент защищённого
  соединения с вашим шлюзом.

## Протоколы

| Платформа | Hysteria2 | VLESS |
|---|---|---|
| Android | да | да |
| Windows | да | да |
| iOS | да | нет |

Hysteria2 — основной транспорт: `hy2://` и `hysteria2://`, включая
`obfs=salamander` и port hopping. VLESS на Android и Windows работает на том же
движке, что и Hysteria2 — `v2fly/v2ray-core` v5.54.2 (MIT) внутри `hy2bind`.
Reality и XHTTP этот движок не описывает, такие строки остаются неактивными.

Trojan, Shadowsocks и VMess парсер читает, но не подключает: смешанный документ
импортируется целиком, а строки, которые платформа не умеет запустить,
показываются с нейтральным бейджем, а не с ошибкой.

## Устройство

```
Flutter UI  (mobile/lib)
      │  MethodChannel proxydom/vpn
      ▼
hy2bind     (mobile/android/hysteria-bind)   Go
      ├── v2fly/v2ray-core v5.54.2  — Hysteria2 и VLESS, MIT
      └── tun2socks                 — TUN → SOCKS
      │
      ├── Android  VpnService, архив gomobile
      ├── iOS      Packet Tunnel Provider
      └── Windows  proxydom-engine.exe + TUN-служба
```

Один и тот же Go-модуль собирается в трёх видах: gomobile-архив для Android,
XCFramework для iOS и обычный `.exe` для Windows. Это сделано намеренно — логика
соединения должна совпадать на всех платформах, а не расходиться по трём
реализациям.

## Документация

| Что нужно | Где |
|---|---|
| Поднять свой сервер Hysteria2 | [`docs/guide/own-hy2-server.md`](docs/guide/own-hy2-server.md) |
| Понять, как вставить ссылку и подключиться | [`docs/guide/using-the-client.md`](docs/guide/using-the-client.md) |
| Что-то не подключается | [`docs/guide/troubleshooting.md`](docs/guide/troubleshooting.md) |
| Windows блокирует запуск (Smart App Control) | [`docs/guide/windows-sac.md`](docs/guide/windows-sac.md) |
| Подписать Windows-сборку, пройти Smart App Control | [`docs/windows-signing.md`](docs/windows-signing.md) |
| Правила для ИИ-агентов | [`AGENTS.md`](AGENTS.md), [`mobile/AGENTS.md`](mobile/AGENTS.md) |

Начать стоит с [`docs/guide/README.md`](docs/guide/README.md) — там оглавление
и три вещи, которые надо понять сразу.

## Сборка

Нужны Flutter 3.24+, Go 1.26+ и JDK 17.

```bash
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test --dart-define=AUTH_ANONYMOUS=false
```

Go-движок собирается отдельно:

```bash
cd mobile/android/hysteria-bind
go test ./...
bash build-aar.sh        # gomobile-архив для Android
```

`build-aar.sh` требует `lief==1.0.0`:

```bash
python -m pip install lief==1.0.0
```

Готовый архив **не коммитится** — это продукт сборки. В CI его собирает джоба
`hy2bind-aar` и передаёт остальным джобам артефактом. Windows-служба и MSI
собираются скриптами в `desktop/windows/installer/`.

MSI для релиза собирается с `-Signing require`: Windows 11 с включённым Smart
App Control не запускает неподписанные программы, а антивирусы не накапливают
репутацию у файла без издателя. Что нужно для подписи и как проверить
результат — [`docs/windows-signing.md`](docs/windows-signing.md).

## Проверка

| Что меняли | Что запустится |
|---|---|
| `mobile/**` | Analyze + Test; Go-тесты, если тронут `hysteria-bind/**` |
| `desktop/windows/**` | Windows Service: CMake + тесты + проверка лицензий payload |
| только документация | ничего |

Зелёный CI не равен работающей сборке. Android и iOS проходят проверку на живом
устройстве, Windows — на живой сессии из локального MSI. Если вы не проверяли
что-то на устройстве, скажите об этом прямо.

## Лицензии

Код — [MIT](LICENSE).

Клиент собирается **только** из permissive-лицензий: MIT, BSD, ISC, Apache-2.0,
MPL-2.0. GPL-3.0 и AGPL-3.0 в сборку не входят и не могут войти — они
несовместимы с условиями App Store, и конфликт здесь про распространение, а не
про цену: §10 запрещает накладывать дополнительные ограничения, §12 при
несовместимости обязательств запрещает распространять произведение вообще.
Поэтому `libbox`, `sing-box` и `xray-core` в этом репозитории не появятся.

Полный список модулей, скомпилированных в движок, с версиями и копирайтами —
[`mobile/assets/legal/THIRD-PARTY-NOTICES.md`](mobile/assets/legal/THIRD-PARTY-NOTICES.md).
Он генерируется из графа зависимостей и попадает в поставку.

## Безопасность

Не открывайте публичный issue на уязвимость — см. [`SECURITY.md`](SECURITY.md).

## Участие

См. [`CONTRIBUTING.md`](CONTRIBUTING.md). Правила для ИИ-агентов —
[`AGENTS.md`](AGENTS.md) и [`mobile/AGENTS.md`](mobile/AGENTS.md).

---

## English

**Proxy Dom** is a local proxy configuration client for Android, iOS and
Windows. You paste a key (`hy2://`, `vless://`, …) or a subscription document
URL, pick a line, and the app brings up a tunnel to that server.

It holds no account, sells no access, issues no keys, and never sends your proxy
credentials anywhere. The key you paste stays on your device. This is a tool,
not a service.

- **Protocols:** Hysteria2 on all three platforms; VLESS on Android and Windows.
  Both run on `v2fly/v2ray-core` v5.54.2 (MIT) inside the `hy2bind` Go module.
  Reality and XHTTP are not implemented and such lines stay inactive.
- **Build:** `cd mobile && flutter pub get && flutter test`. The Go engine lives
  in `mobile/android/hysteria-bind/` and is compiled by `build-aar.sh`; the
  archive is a build product and is not committed.
- **Licence:** MIT. The shipped client contains permissive licences only
  (MIT, BSD, ISC, Apache-2.0, MPL-2.0). GPL-3.0 and AGPL-3.0 cannot be added:
  they are incompatible with the App Store terms regardless of whether the app
  is paid, because the conflict is about distribution rather than price.
- **Security:** report privately, see [`SECURITY.md`](SECURITY.md).
