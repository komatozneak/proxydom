# Teremok Connect — мобильный клиент

> **SoT 2026-08-17.** Android: Flutter + **Hysteria2 only** (ADR 018), minSdk **26**.  
> Auth: anonymous `device_uuid` + recovery. Касса: **Platega hosted** (ADR 017) — не Play Billing, не копировать Billing AAR из Огня.  
> Правила: [`mobile/AGENTS.md`](./AGENTS.md), корневой [`AGENTS.md`](../AGENTS.md).

## Стек

- Flutter + Riverpod + go_router + Dio
- MethodChannel `teremok/vpn`
- Paywall: `LockedAccessScreen` → `BillingApi.createPlategaPayment` → внешний `redirectUrl`

## Команды

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

`flutter run` ставит `com.teremok.connect.teremok_connect.debug`. APK для сайта / Pixel — только с upload keystore:

```powershell
cd mobile\android
.\build-sideload.ps1
```

`flutter build apk --release` без `key.properties` даёт CI-пакет `…teremok_connect.ci` (debug-подпись), его нельзя класть в `/downloads`.

Прод API по умолчанию; эмулятор: `--dart-define=APP_ENV=dev`.

## Не делать

- Не возвращать libbox / sing-box / Flash Call.
- Не добавлять `com.android.vending.BILLING`.
- Не хардкодить `Color(0xFF…)` — только `AppBrand` / `ColorScheme`.
