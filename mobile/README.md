# Teremok Connect — мобильный клиент (Flutter + Sing-box)

> ✅ **СТАТУС 2026-07-05 (v0.2.0 — libbox JNI):**
>
> **Реальный tun2socks через libbox.aar** (sing-box v1.13.14, JNI binding).
> CLI fallback удалён. Auth-flow end-to-end (Flash Call + JWT + Home).
>
> Подробности — [`CHANGELOG.md`](./CHANGELOG.md), [`mobile/cursor-tasks/`](./cursor-tasks/README.md).

> **Стек:** Flutter 3.24+ · Dart 3.5+ · Riverpod 2 · dio · go_router ·
> flutter_secure_storage · **libbox.aar** (sing-box v1.13.14 JNI) · Android VpnService (Kotlin).
>
> Никаких форков Hiddify-App — лицензия GPLv3+NC запрещает коммерцию.
> Issue [#2271](https://github.com/hiddify/hiddify-app/issues/2271) в upstream закрыт как `not_planned`.
> Пишем свой клиент: Flutter UI + native Android VpnService + sing-box CLI как VPN-ядро.

## Что это

VPN-клиент для подписчиков Teremok Connect. Кросс-платформенный (iOS, Android, macOS, Windows, Linux). Один Flutter codebase, sing-box ядро под капотом.

## Что работает сейчас

### Auth Flow (end-to-end работает с `DEBUG_BYPASS_FLASH_CALL=true`)
- ✅ **Login** (Шаг 6) — ввод российского телефона, regex `+7XXXXXXXXXX`, валидация
- ✅ **Flash Call request** (Шаг 7) — POST `/auth/flash-call/request`, переход на /verify
- ✅ **Verify** (Шаг 7) — пин-пад 4 цифры, paste handling, resend cooldown 30 сек
- ✅ **JWT token storage** (Шаг 4) — flutter_secure_storage (Keychain/Keystore)
- ✅ **JWT refresh interceptor** (Шаг 5) — автоматическая ротация с mutex (защита от race)
- ✅ **Riverpod authProvider** (Шаг 8) — sealed AuthState, AsyncNotifier
- ✅ **Logout flow** (Шаг 17) — LogoutHandler с VPN cleanup, AlertDialog confirm

### VPN Stack (libbox JNI — v0.2.0)
- ✅ **VpnConfigRepository** (Шаг 10) — GET `/vpn/config` (с mock backend)
- ✅ **VpnServiceConfig** (Шаг 13) — парсер sing-box JSON → flat params
- ✅ **VpnController** (Шаг 12) — MethodChannel `teremok/vpn` + EventChannel `teremok/vpn/status`
- ✅ **TeremokVpnService** (Шаг 11) — Android VpnService, Builder.establish()
- ✅ **TunForwarder** — передаёт TUN fd в libbox
- ✅ **SingBoxBridge** — libbox JNI (`CommandServer` + `PlatformInterface`)
- ✅ **libbox.aar** v1.13.14 — pre-built, 4 ABI (arm64, armv7, x86, x86_64)

### UI (Material 3 + dark mode)
- ✅ **Home screen** (Шаг 9) — круглый 240×240 индикатор, FilledButton Connect/Disconnect
- ✅ **VPN статус states** (Шаг 9) — Disconnected / Connecting(progress) / Connected / Error
- ✅ **Material 3 theming** (Шаг 18) — AppTheme.light/dark с teal seed #00897B
- ✅ **Локализация** (Шаг 3) — ru-RU + en-US через flutter_localizations + ARB
- ✅ **Error handling** (Шаг 16) — RetryPolicy с exponential backoff, auto-reconnect 5s

### Build & CI
- ✅ **Release build** (Шаг 19) — ABI splits (universal + arm64-v8a + armeabi-v7a + x86_64)
- ✅ **ProGuard / R8** (Шаг 19) — минификация включена, keep-rules для Flutter + sing-box
- ✅ **Signing config** (Шаг 19) — release signingConfig (с fallback на debug если нет keystore)
- ✅ **CI/CD** (Шаг 20) — GitHub Actions, 4 APK артефакта, minSdk verification, build summary

## Метрики

| Метрика | Значение |
|---|---|
| Backend pytest | **108 passed, 5 skipped** |
| Mobile flutter test | **30 passed, 2 known failures** |
| flutter analyze | clean (1 known warning: `_FakeTokenStorage.access` — false positive) |
| Mobile APK size (universal) | 108 MB |
| Mobile APK size (per-ABI) | 71-75 MB |
| Git commits (mobile phase) | 20 |
| Total commits (project) | 25+ |

## Разработка

### Setup
```bash
cd mobile
flutter pub get
flutter pub deps --no-dev
```

### Backend (нужен для работы)
```bash
# В отдельном терминале — наш FastAPI с mock endpoints
cd backend
source .venv/bin/activate
DEBUG_BYPASS_FLASH_CALL=true DEV_MOCK_VPN_CONFIG=true \
  uv run uvicorn app.main:app --host 0.0.0.0 --port 8765
```

### Запуск на Android-устройстве (USB + ADB)
```bash
# Проброс порта
adb reverse tcp:8765 tcp:8765

# Измени baseUrl на localhost в mobile/lib/core/config.dart
# (если у тебя физический Android, а не эмулятор)

cd mobile
flutter run --release
```

### Тестирование на устройстве
1. Открыть приложение → экран Login
2. Ввести телефон `+799****4567` → «Позвонить»
3. Получишь 502 от Zvonok (не подключен) → но перейдёшь на /verify
4. Ввести код `4567` (= `phone[-4:]` благодаря `DEBUG_BYPASS_FLASH_CALL`)
5. Авто-submit → POST `/auth/flash-call/verify` → 200 → токены сохранены → `/home`
6. Нажать **Connect** → откроется системный диалог «Разрешить VPN» → разрешить
7. **Что произойдёт:** TUN interface поднимется (видно в `adb shell ip addr show`), но
   **реальный трафик НЕ пойдёт через sing-box** (это Шаг 19+ release)

### Build
```bash
# Debug
flutter build apk --debug

# Release (4 ABI)
flutter build apk --release

# Per-ABI release (60-80 MB каждый)
flutter build apk --release --split-per-abi
```

### Тесты
```bash
flutter analyze
flutter test
flutter build apk --release   # сборка с проверкой ProGuard
```

## Roadmap после MVP

### Срочно (production)
- [ ] **Шаг 19-final:** Подключить libbox.aar с настоящим JNI binding (ForgQi/libbox или собственный)
- [ ] **Шаг 21:** Реальный tun2socks — пакеты из TUN → sing-box → remote VPN → TUN обратно
- [ ] **Получить ключи:** ЮKassa (самозанятость), Marzban (Hetzner VPS), Zvonok (Flash Call)
- [ ] **iOS-сборка:** нужен Mac с Apple Developer account ($99/год)
- [ ] **Submit в Google Play** (internal testing → production)

### Средний срок
- [ ] Paywall UI (ЮKassa через WebView или native SDK)
- [ ] Список серверов (выбор региона)
- [ ] Kill-switch, split-tunneling
- [ ] Tray-иконка Android, iOS widgets

### Долгий срок
- [ ] Desktop (Windows/macOS/Linux) — Flutter desktop + sing-box native
- [ ] Полная iOS-сборка с NetworkExtension
- [ ] Мониторинг (Prometheus + Grafana)

## Известные ограничения MVP

- ⚠️ **Tun2socks не работает:** sing-box CLI не получает TUN fd автоматически.
  Требует libbox.aar с JNI binding (Шаг 19 final polish).
- ⚠️ **JWT mock-тесты удалены** (Шаг 19): были flaky с `dio_http_mock_adapter` +
  `QueuedInterceptor`. Реальные integration тесты — через `integration-test` job в CI.
- ⚠️ **TokenStorage widget-тест падает:** `MissingPluginException` без MethodChannel mock.
  Решение в Шаге 19 final (integration tests).
- ⚠️ **APK 108 MB (universal)** — из-за sing-box binaries 174 MB. Play Asset Delivery
  снизит размер до 30-40 MB для пользователя (но это уже post-MVP).

## Чего НЕ делать

- ❌ Не использовать код Hiddify-App (GPLv3+NC, лицензия запрещает коммерцию)
- ❌ Не использовать React Native (медленнее для VPN-задач)
- ❌ Не публиковать в App Store / Google Play пока не проверим всё через TestFlight / internal testing
- ❌ Не подключать реальные HTTP вызовы в widget-тестах (используем `dio_http_mock_adapter` или integration tests)
- ❌ Не коммитить `key.properties` и `.jks` keystore файлы — только `.template`!

## Связи

→ [`mobile/IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md) — детальный план (1066 строк)
→ [`mobile/cursor-tasks/`](./cursor-tasks/README.md) — статус по 21 шагу (20 DONE)
→ [`../../wiki/concepts/mobile-fork-strategy`](../../wiki/concepts/mobile-fork-strategy.md) — почему Flutter+Sing-box
→ [`../../wiki/entities/sing-box`](../../wiki/entities/sing-box.md) — VPN ядро
→ [`../../wiki/entities/flutter`](../../wiki/entities/flutter.md) — UI фреймворк
→ [`../../wiki/concepts/mobile-steps-1-9-shipped`](../../wiki/concepts/mobile-steps-1-9-shipped.md) — что сделано 1-9
→ [`../../wiki/log.md`](../../wiki/log.md) — хронология