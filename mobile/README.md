# Proxy Dom — мобильный клиент

> Локальный конфигуратор Hysteria2 (ADR 033). minSdk **26**. Пакет Play: `com.proxy.dom`.  
> Правила: [`mobile/AGENTS.md`](./AGENTS.md), корневой [`AGENTS.md`](../AGENTS.md).

## Стек

- Flutter + Riverpod + go_router
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

- Не возвращать libbox / sing-box / Flash Call.
- Не добавлять `com.android.vending.BILLING`.
- Не хардкодить `Color(0xFF…)` — только `AppBrand` / `ColorScheme`.
