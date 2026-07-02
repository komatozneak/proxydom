# Teremok Connect — мобильный клиент

> **Статус**: в разработке. План — форк [Hiddify-App](https://github.com/hiddify/hiddify-app) (Flutter) с кастомным UI/брендингом и интеграцией с нашим backend.

## Цель форка

1. Переименовать под **Teremok Connect**
2. Подключить к нашему backend (`api.teremok-connect.ru`)
3. Заменить UI-тексты и брендинг
4. Добавить авторизацию по телефону (Flash Call → поле для 4 цифр)
5. Интегрировать с Telegram-ботом для саппорта

## Roadmap

- [ ] Форк Hiddify-App → `teremok-connect/mobile`
- [ ] Кастомизация брендинга (иконка, splash, цвета)
- [ ] Подключение к нашему backend
- [ ] Авторизация Flash Call (UI + логика)
- [ ] In-app support (открытие Telegram-бота)
- [ ] Push-уведомления (FCM) для обновлений конфигов
- [ ] Deep links (`teremok://import-config?url=...`)
- [ ] Подписочная модель (In-App Purchases + WebView fallback на ЮKassa)

## Разработка

```bash
cd mobile
flutter pub get
flutter run                    # на эмуляторе/устройстве
flutter test                   # тесты
flutter build apk --release    # Android
flutter build ios --release    # iOS
```

## Ключевые ссылки

- [[../~/LLM-Wiki/entities/hiddify-app]] — описание upstream
- [[../~/LLM-Wiki/entities/hiddify-app-settings-deepwiki-2026-07]] — карта кодовой базы
- [[../~/LLM-Wiki/entities/vpn-under-china-reality-kiwi-habr-1053250-2026-06]] — UX-флоу через bridge page + deeplink

## Когда нанимать разработчика

Форк + кастомизация UI = **2–4 недели** для вайбкодера с Cursor + Claude 4.5.

Если времени нет — найми Flutter-разработчика на 1–2 месяца:
- Стоимость: 80–150 тыс. ₽/мес
- Искать: Telegram-чаты Flutter-комьюнити, hh.ru, Хабр Фриланс

## Чего НЕ делать

- ❌ Не пиши с нуля свой VPN-клиент (потеря 6+ месяцев)
- ❌ Не используй React Native (медленнее Flutter для нашего кейса)
- ❌ Не забывай про iOS — нужен разработчик для App Store review