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
flutter build apk --release
```

Прод API по умолчанию; эмулятор: `--dart-define=APP_ENV=dev`.

## Не делать

- Не возвращать libbox / sing-box / Flash Call.
- Не добавлять `com.android.vending.BILLING`.
- Не хардкодить `Color(0xFF…)` — только `AppBrand` / `ColorScheme`.
