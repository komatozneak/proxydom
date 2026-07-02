# Teremok Connect — мобильный клиент (Flutter + Sing-box)

> ✅ **СТАТУС 2026-07-02 (rev 3):**
> Решение по мобильному клиенту **финализировано**.
> Пишем сами на Flutter (UI) + Sing-box (VPN-ядро, GPLv3 без NC).
> Никаких форков Hiddify-App — лицензия GPLv3+NC запрещает коммерцию без permission.
> Issue [#2271](https://github.com/hiddify/hiddify-app/issues/2271) в upstream закрыт как `not_planned`.
>
> Подробности и обоснование: [`../../wiki/concepts/mobile-fork-strategy`](../../wiki/concepts/mobile-fork-strategy.md).

## Что это

VPN-клиент для подписчиков Teremok Connect. Кросс-платформенный (iOS, Android, macOS, Windows, Linux). Один Flutter codebase, sing-box ядро под капотом.

## Стек

- **UI:** Flutter 3.x + Dart, Riverpod 2
- **VPN ядро:** sing-box (Go) через FFI binding
- **HTTP:** dio → наш FastAPI backend (`/vpn/config`, `/auth/flash-call/*`)
- **Хранилище:** flutter_secure_storage (Keychain / EncryptedSharedPreferences)
- **Навигация:** go_router

## Roadmap

- [ ] Перенести существующий прототип пользователя из Cursor в `mobile/`
- [ ] Настроить `pubspec.yaml` (flutter + dio + riverpod + secure_storage)
- [ ] Подключить sing-box через FFI bridge
- [ ] Экран авторизации Flash Call (как в backend Phase 2)
- [ ] Главный экран: статус подключения + кнопка Вкл/Выкл
- [ ] Экран настроек (серверы, протоколы, theme)
- [ ] UI Paywall (ЮKassa через WebView)
- [ ] Локализация ru-RU + en-US
- [ ] CI: GitHub Actions (Android/Windows/Linux) + Codemagic (iOS/macOS)

## Разработка

```bash
cd mobile
flutter pub get
flutter run                    # на эмуляторе/устройстве
flutter test                   # тесты
flutter build apk --release    # Android
flutter build ios --release    # iOS (нужен Mac или Codemagic)
```

## Когда нанимать разработчика

Если MVP на Flutter готов, но нужны:
- Углубленные фичи (kill-switch, split-tunneling, custom DNS)
- Оптимизация производительности
- Сложные платформенные интеграции

Тогда ищем Flutter-разработчика на 1-2 месяца (80-150 тыс. ₽/мес по плану `vibecoder-roadmap`).

## Чего НЕ делать

- ❌ Не использовать код Hiddify-App (GPLv3+NC, лицензия запрещает коммерцию)
- ❌ Не использовать React Native (медленнее для VPN-задач)
- ❌ Не публиковать в App Store / Google Play пока не проверим всё через TestFlight / internal testing

## Связи

→ [`../../wiki/concepts/mobile-fork-strategy`](../../wiki/concepts/mobile-fork-strategy.md) — детальная стратегия
→ [`../../wiki/entities/sing-box`](../../wiki/entities/sing-box.md) — VPN ядро
→ [`../../wiki/entities/flutter`](../../wiki/entities/flutter.md) — UI фреймворк
