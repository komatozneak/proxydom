# Proxy Dom — мобильный клиент

> Локальный конфигуратор прокси: Hysteria2 на всех платформах, VLESS на Android.
> minSdk **26**. Пакет Play: `com.proxy.dom`.
> Правила: [`mobile/AGENTS.md`](./AGENTS.md), корневой [`AGENTS.md`](../AGENTS.md).

## Стек

- Flutter + Riverpod + go_router
- Движок: `hy2bind` — Go, `v2fly/v2ray-core` v5.54.2 (MIT) и `apernet/hysteria`
- MethodChannel `proxydom/vpn`

## Команды

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

`flutter run` ставит `com.proxy.dom.debug`. APK для сайта / Pixel — только с upload keystore:

```powershell
cd mobile\android
.\build-sideload.ps1
```

`flutter build apk --release` без `key.properties` даёт CI-пакет `com.proxy.dom.ci` (debug-подпись), его нельзя класть в `/downloads`.

Прод API по умолчанию; эмулятор: `--dart-define=APP_ENV=dev`.

## Не делать

- Не возвращать `libbox` / `sing-box` / `xray-core` — это GPL-3.0, он не может
  входить в поставку (см. корневой `AGENTS.md` и `android/app/libs/README.md`).
- Не добавлять `com.android.vending.BILLING`.
- Не хардкодить `Color(0xFF…)` — только `AppBrand` / `ColorScheme`.
