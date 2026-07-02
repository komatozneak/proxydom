# Teremok Connect — Mobile: Cursor-ассистируемый план разработки

> **Аудитория:** вайбкодер. Не пишет код руками. Работает в Cursor IDE + Claude.
> Копирует задачу в Cursor → Cursor генерирует код → юзер проверяет на Android через ADB-USB → commit → следующая задача.
>
> **Стек:** Flutter 3.x stable + Dart 3.x, Riverpod 2, dio, go_router, flutter_secure_storage, sing-box v1.13.14 как VPN-ядро.
>
> **Один commit = одна задача из этого документа.**

---

## 0. Acceptance criteria (что должна делать итоговая сборка)

Минимальный жизнеспособный продукт (MVP) для Android:

1. **APK скачивается с нашего сайта** (или ставится через `adb install`).
2. **При первом запуске** показывается экран ввода телефона.
3. **Юзер вводит телефон** в формате `+7XXXXXXXXXX` → нажимает "Получить звонок" → backend делает Flash Call через Zvonok.
4. **Юзер вводит 4 последние цифры** входящего звонка → backend выдаёт пару JWT (access + refresh).
5. **Токены сохраняются** в flutter_secure_storage. При перезапуске приложения юзер остаётся залогинен.
6. **Главный экран:** большой круглый индикатор "Отключено/Подключено" + кнопка Connect/Disconnect + кнопка Logout.
7. **По нажатию Connect** приложение запрашивает `/vpn/config` → получает sing-box JSON → парсит → запускает sing-box через Android `VpnService` → VPN реально поднимается (видно в системных настройках Android в разделе VPN).
8. **По нажатию Disconnect** VPN корректно завершается.
9. **При истечении access-токена** (15 мин) dio interceptor автоматически вызывает refresh endpoint → юзер не замечает разрыва.
10. **Юзер может выйти** из аккаунта → токены удаляются → редирект на экран логина.

**Out of scope для MVP (делаем позже):** paywall UI, список серверов, kill-switch, split-tunneling, tray-иконка, мультипротокольный выбор, iOS-сборка, десктопы.

---

## ⚠️ Критический нюанс, который нужно решить ДО старта

**Backend НЕ имеет `POST /auth/refresh` endpoint** (см. `AGENTS.md`, раздел "Что НЕ сделано").

В `app/core/security.py` есть `create_refresh_token()`, в `TokenResponse` есть `refresh_token`, но роутера для обмена refresh→new access нет.

**Что делаем:** в задаче **#1** ниже я включаю подзадачу "попроси Cursor добавить `POST /auth/refresh` в backend" перед началом мобильной разработки. Без этого auto-refresh на клиенте работать не будет — придётся после 15 мин логиниться заново.

**Альтернатива (если не хочешь трогать backend сейчас):** MVP-режим без авто-refresh. Access живёт 15 мин, потом приложение выкидывает на логин. Юзер звонит ещё раз. Это некрасиво, но работает. Рекомендую всё-таки добавить endpoint — 5 строк кода.

---

## 1. Этапы разработки (последовательность коммитов)

Каждый этап = **один commit**. В конце каждого этапа — ручная проверка.

| # | Этап | Что делает Cursor | Что проверяет юзер | Время |
|---|------|-------------------|--------------------|-------|
| 0 | **Backend: добавить `/auth/refresh`** | Новый роутер в `backend/app/api/v1/auth.py` | `curl -X POST localhost:8000/auth/refresh -d '{"refresh_token":"..."}'` | 10 мин |
| 1 | **Bootstrap Flutter-проекта** | `flutter create`, базовый `main.dart`, `pubspec.yaml`, тема | `flutter run` показывает белый экран "Hello Teremok" | 20 мин |
| 2 | **Структура lib/ + go_router скелет** | Папки core/features/infrastructure, go_router с двумя роутами (login + home) | Навигация работает, экран переключается кнопкой | 30 мин |
| 3 | **Локализация ru-RU + en-US** | `flutter_localizations`, `intl`, ARB-файлы, LanguageProvider | В настройках можно переключить язык, всё меняется | 30 мин |
| 4 | **dio + baseUrl + secure storage** | `ApiClient`, `TokenStorage`, base config | Логи в `flutter run` показывают правильный URL | 20 мин |
| 5 | **JWT interceptor + refresh** | `JwtInterceptor` с мьютексом (защита от race) | Проверка: ждём 16 мин → запрос не падает, токен обновляется | 1 час (с отладкой) |
| 6 | **Экран Login: ввод телефона** | Виджет, валидация, кнопка, вызов `/auth/flash-call/request` | Телефон принимается, кнопка триггерит запрос, в логе видно 202 | 30 мин |
| 7 | **Экран Verify: ввод 4 цифр** | Пин-пад, вызов `/auth/flash-call/verify`, сохранение токенов, редирект на home | Полный flash-call цикл на реальном номере проходит | 1 час |
| 8 | **Riverpod state для auth** | `authProvider` (AsyncNotifier) с состояниями loading/authenticated/unauthenticated | После logout state корректно сбрасывается | 30 мин |
| 9 | **Экран Home: UI заглушка** | Большой круглый индикатор, кнопка Connect/Disconnect, Logout | UI выглядит как на макете | 30 мин |
| 10 | **VPN config fetch + модель** | `VpnConfigRepository`, вызов `/vpn/config`, парсинг JSON, кеш в памяти | Логи показывают полученный sing-box JSON, нет 401 | 45 мин |
| 11 | **Android VpnService скелет** | Kotlin-класс `TeremokVpnService`, манифест с `BIND_VPN_SERVICE` | При ручном старте из тестового активити появляется системный диалог "Разрешить VPN" | 1.5 часа |
| 12 | **MethodChannel: Flutter ↔ VpnService** | `VpnController` в Dart, channel `teremok/vpn`, методы `start/stop` | Из Flutter кнопка стартует/останавливает VPN (без реального трафика пока) | 1.5 часа |
| 13 | **Парсинг sing-box JSON → VpnService config** | Трансляция sing-box outbound в Android `Builder` параметры (address/port/protocol) | Тестовый sing-box конфиг отдает VPN, в логах VpnService видно `establishing` | 2 часа |
| 14 | **Подключение sing-box native binary** | Скачать sing-box-android-arm64-v8a.aar, положить в `android/app/libs`, подключить в Gradle | APK собирается, sing-box.so внутри, нет unresolved references | 2 часа |
| 15 | **Гоняем трафик через sing-box** | Нативный код в VpnService читает пакеты из `ParcelFileDescriptor`, передаёт в sing-box через JNI | `adb shell ping 8.8.8.8` из терминала ПК проходит через VPN (видно в `sing-box stats`) | 4 часа |
| 16 | **Обработка ошибок и reconnect** | Таймауты, retry на сбой sing-box, snackbar юзеру | Выключаем Marzban на 5 сек → приложение показывает ошибку, не падает | 1.5 часа |
| 17 | **Logout flow** | Кнопка, очистка токенов, остановка VPN, редирект | После logout нельзя вернуться назад кнопкой "назад" | 20 мин |
| 18 | **Material 3 темизация** | `ColorScheme.fromSeed`, поддержка dark mode, splash, кнопки в стиле Material 3 | На устройстве переключаем dark mode — приложение реагирует | 1 час |
| 19 | **Release-сборка + подпись** | `key.properties`, `build.gradle` signing config | `flutter build apk --release` собирает подписанный APK | 1 час |
| 20 | **CI: GitHub Actions для Android** | `.github/workflows/mobile-android.yml` с build + upload артефакта | Push в `feat/mobile-*` → в Actions появляется APK | 1 час |

**Итого MVP (Android):** примерно **25-30 часов** чистой работы Cursor + юзер. С учётом отладки и "а почему не работает" — реалистично **2-3 недели** в режиме вайбкодера по 2-3 часа в день.

---

## 2. Структура `mobile/` директории

### 2.1 `pubspec.yaml` (версии подобраны под стабильный Flutter 3.24+, Dart 3.5+)

```yaml
name: teremok_connect
description: Teremok Connect — VPN клиент для подписчиков
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: '>=3.5.0 <4.0.0'
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # State
  flutter_riverpod: ^2.5.1

  # HTTP + Interceptors
  dio: ^5.7.0

  # Routing
  go_router: ^14.6.0

  # Storage
  flutter_secure_storage: ^9.2.2

  # Localization helper
  intl: ^0.19.0

  # Connectivity (проверка состояния сети)
  connectivity_plus: ^6.1.0

  # Device info (для /api/v1/users/me)
  device_info_plus: ^11.0.0

  # Permissions (для runtime запросов Android)
  permission_handler: ^11.3.1

  # Logging (dev)
  logger: ^2.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.4

flutter:
  uses-material-design: true
  generate: true  # для локализации через gen-l10n
```

### 2.2 Дерево `lib/`

```
mobile/
├── android/                          # Android-специфичное
│   ├── app/
│   │   ├── build.gradle              # подключение sing-box AAR
│   │   └── src/main/
│   │       ├── AndroidManifest.xml   # BIND_VPN_SERVICE + FOREGROUND_SERVICE
│   │       └── kotlin/.../vpn/
│   │           ├── TeremokVpnService.kt   # extends VpnService
│   │           ├── SingBoxRunner.kt       # JNI к sing-box
│   │           └── VpnConfigMapper.kt     # sing-box JSON → Android Builder
│   └── app/libs/
│       └── sing-box-android-arm64.aar  # sing-box бинарь
│
├── ios/                              # P1, для Codemagic
├── lib/
│   ├── main.dart                     # точка входа
│   ├── app.dart                      # MaterialApp + ProviderScope + Router
│   │
│   ├── core/                         # общее для всех фич
│   │   ├── config/
│   │   │   └── app_config.dart       # baseUrl, environment enum
│   │   ├── theme/
│   │   │   ├── app_theme.dart        # Material 3 ColorScheme
│   │   │   └── theme_provider.dart   # Riverpod: light/dark/system
│   │   ├── errors/
│   │   │   └── app_exception.dart    # кастомные исключения
│   │   └── utils/
│   │       └── logger.dart           # обёртка над logger
│   │
│   ├── features/                     # фичи (каждая со своим ui/data/domain)
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── auth_repository.dart
│   │   │   │   └── auth_models.dart  # TokenResponse, User
│   │   │   ├── ui/
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── verify_screen.dart
│   │   │   └── auth_provider.dart    # Riverpod AsyncNotifier
│   │   │
│   │   ├── home/
│   │   │   └── ui/
│   │   │       └── home_screen.dart  # статус + Connect/Disconnect
│   │   │
│   │   └── vpn/
│   │       ├── data/
│   │       │   └── vpn_repository.dart   # вызов /vpn/config
│   │       ├── domain/
│   │       │   └── vpn_state.dart        # enum: disconnected/connecting/connected/error
│   │       └── vpn_provider.dart         # Riverpod Notifier
│   │
│   ├── infrastructure/               # внешние зависимости (Dio, Storage)
│   │   ├── network/
│   │   │   ├── api_client.dart       # Dio singleton
│   │   │   ├── jwt_interceptor.dart  # auto-refresh при 401
│   │   │   └── retry_interceptor.dart
│   │   └── storage/
│   │       └── token_storage.dart    # обёртка flutter_secure_storage
│   │
│   └── l10n/
│       ├── app_en.arb
│       └── app_ru.arb
│
├── test/
│   └── ...                           # юнит-тесты для repository, interceptor
└── pubspec.yaml
```

### 2.3 Android permissions

В `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- VPN -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    
    <!-- Network state для kill-switch -->
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application ...>
        <activity android:name=".MainActivity" ...>
            <!-- стандартный конфиг -->
        </activity>

        <!-- VPN service -->
        <service
            android:name=".vpn.TeremokVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="false">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
    </application>
</manifest>
```

**Пояснения:**
- `BIND_VPN_SERVICE` — обязательно для сервиса, который реализует VPN.
- `FOREGROUND_SERVICE` — Android 8+ требует, чтобы VPN-сервис был foreground (иначе убьёт через 5 сек).
- `FOREGROUND_SERVICE_SPECIAL_USE` — Android 14+ требует указания типа foreground-сервиса. Альтернатива: `systemExempted` для VPN (API 33+).
- `ACCESS_NETWORK_STATE` — чтобы UI показывал реальный статус (ConnectivityResult).

### 2.4 iOS permissions (для будущего)

В `ios/Runner/Info.plist` добавить:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Teremok Connect использует VPN для защиты вашего трафика.</string>
```

В Xcode Capabilities включить:
- **Network Extensions** (Personal VPN)
- **Packet Tunnel Provider** (для VPN-протоколов)
- **App Groups** (для sharing данных между app и extension)

Provisioning profile должен содержать `com.apple.developer.networking.networkextension` capability.

---

## 3. Подробный план по фичам

### 3.1 Auth flow (Flash Call)

**Backend endpoints (готовы):**
- `POST /auth/flash-call/request` — body: `{"phone": "+7XXXXXXXXXX"}`, response: `{"status": "sent"}`
- `POST /auth/flash-call/verify` — body: `{"phone": "+7...", "last_4": "1234"}`, response: `{"access_token": "...", "refresh_token": "...", "token_type": "bearer"}`
- `POST /auth/refresh` — **ДОБАВИТЬ САМОМУ ПЕРВЫМ**, body: `{"refresh_token": "..."}`, response: `TokenResponse`
- `GET /api/v1/users/me` — требует `Authorization: Bearer <access_token>`, возвращает профиль

**Логика на клиенте:**

```
[Login Screen]                    [Verify Screen]                [Home Screen]
  │                                  │                              │
  ├─── POST /flash-call/request ────►│                              │
  │◄── 202 {"status":"sent"} ────────┤                              │
  │                                  │                              │
  ├─── navigate ────────────────────►│                              │
  │                                  ├─── POST /flash-call/verify ─►│
  │                                  │◄── 200 {access, refresh} ───┤
  │                                  │                              │
  │                                  │  TokenStorage.save()         │
  │                                  ├─── GET /users/me ──────────►│
  │                                  │◄── 200 {phone, ...} ────────┤
  │                                  │                              │
  │                                  ├─── navigate ────────────────►│
```

**Задача для Cursor (Task #6 + #7):**

> "Создай экран логина в `lib/features/auth/ui/login_screen.dart`. Поле для телефона с маской `+7 (XXX) XXX-XX-XX`, валидацией формата E.164 и кнопкой 'Получить звонок'. По нажатию — вызов `POST http://localhost:8000/auth/flash-call/request` через наш `ApiClient`. При успехе (202) — редирект на `VerifyScreen` с передачей `phone`. При ошибке — snackbar с текстом ошибки. Используй Riverpod `ref.read(authProvider.notifier)` для actions. Стиль Material 3, primary color из темы."

### 3.2 JWT refresh interceptor

**Проблема:** access token живёт 15 мин. Если юзер сидит в приложении дольше — все запросы начнут падать с 401.

**Решение:** dio interceptor с мьютексом (защита от race condition).

```dart
// lib/infrastructure/network/jwt_interceptor.dart
class JwtInterceptor extends Interceptor {
  JwtInterceptor(this._tokenStorage, this._refreshApi);

  final TokenStorage _tokenStorage;
  final Future<bool> Function() _refreshApi;
  bool _isRefreshing = false;
  final _pendingRequests = <Completer<void>>[];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Если уже идёт refresh — подожди
    if (_isRefreshing) {
      final completer = Completer<void>();
      _pendingRequests.add(completer);
      try {
        await completer.future;
        return handler.resolve(await _retry(err.requestOptions));
      } catch (_) {
        return handler.next(err);
      }
    }

    _isRefreshing = true;
    try {
      final ok = await _refreshApi();
      if (!ok) {
        _failAll(err, handler);
        return;
      }
      // Уведомить всех ожидающих
      for (final c in _pendingRequests) {
        c.complete();
      }
      _pendingRequests.clear();
      return handler.resolve(await _retry(err.requestOptions));
    } catch (e) {
      _failAll(err, handler);
      return handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions opts) async {
    final newToken = await _tokenStorage.readAccess();
    opts.headers['Authorization'] = 'Bearer $newToken';
    return Dio().fetch(opts);  // повтор без interceptor
  }

  void _failAll(DioException err, ErrorInterceptorHandler handler) {
    for (final c in _pendingRequests) {
      c.completeError(err);
    }
    _pendingRequests.clear();
    handler.next(err);
  }
}
```

**Зачем мьютекс:** если два запроса одновременно получат 401 (например, фоновый polling + юзер нажал кнопку), без мьютекса оба пошлют refresh → два новых refresh токена → один из них невалиден. С `Completer` все ожидающие ждут одного refresh.

### 3.3 Хранилище токенов

```dart
// lib/infrastructure/storage/token_storage.dart
class TokenStorage {
  TokenStorage(this._storage);
  final FlutterSecureStorage _storage;

  static const _kAccess = 'auth.access_token';
  static const _kRefresh = 'auth.refresh_token';

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> readAccess() => _storage.read(key: _kAccess);
  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  Future<void> updateAccess(String access) =>
      _storage.write(key: _kAccess, value: access);

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
```

**Почему `flutter_secure_storage`, а не `shared_preferences`:** обычный `shared_preferences` хранит в plain text в XML-файле — токены видны через `adb backup`. Secure storage использует Android Keystore (шифрование AES-GCM) и iOS Keychain. Для production это обязательно.

### 3.4 VPN config fetch

```dart
// lib/features/vpn/data/vpn_repository.dart
class VpnRepository {
  VpnRepository(this._apiClient);
  final ApiClient _apiClient;

  Future<VpnConfig> fetchConfig() async {
    // GET /vpn/config — возвращает sing-box links[]
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/vpn/config');
    final data = response.data!;

    // Преобразуем vless://... link в sing-box JSON outbound
    final links = (data['links'] as List).cast<String>();
    final outbounds = links.map(_linkToOutbound).toList();

    return VpnConfig(
      username: data['username'] as String,
      expire: DateTime.fromMillisecondsSinceEpoch((data['expire'] as int) * 1000),
      outbounds: outbounds,
    );
  }

  Map<String, dynamic> _linkToOutbound(String link) {
    // Парсим vless://uuid@host:port?... (минимальный парсер)
    // И возвращаем структуру sing-box outbound
    // Для MVP достаточно распарсить VLESS+Reality — основной протокол
    final uri = Uri.parse(link);
    if (uri.scheme != 'vless') {
      throw FormatException('Unsupported scheme: ${uri.scheme}');
    }
    final params = uri.queryParameters;
    return {
      'type': 'vless',
      'tag': 'proxy',
      'server': uri.host,
      'server_port': uri.port,
      'uuid': uri.userInfo,
      'flow': params['flow'],
      'reality': {
        'enabled': params['security'] == 'reality',
        'public_key': params['pbk'],
        'short_id': params['sid'],
      },
    };
  }
}
```

**Полный sing-box JSON config (для сравнения — backend НЕ возвращает это, собираем на клиенте):**

```json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "tun",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true
    }
  ],
  "outbounds": [
    { "type": "vless", "...": "..." }  // из /vpn/config
  ]
}
```

**Почему собираем на клиенте, а не берём готовый с backend:** backend отдаёт `vless://...` ссылки (для совместимости с другими клиентами), но sing-box принимает JSON. Чтобы не плодить два формата на сервере — парсим на клиенте.

### 3.5 Парсинг sing-box JSON

В `lib/features/vpn/data/vpn_repository.dart` после получения `links[]` мы собираем финальный конфиг:

```dart
Map<String, dynamic> buildSingBoxConfig(VpnConfig vpnConfig) {
  return {
    'log': {'level': 'info'},
    'dns': {
      'servers': [
        {'tag': 'google', 'address': '8.8.8.8'},
        {'tag': 'local', 'address': 'localhost'},
      ],
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'inet4_address': '172.19.0.1/30',
        'auto_route': true,
        'strict_route': true,
        'sniff': true,
      },
    ],
    'outbounds': vpnConfig.outbounds + [
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
    ],
    'route': {
      'rules': [
        {'action': 'sniff'},
        {'protocol': 'dns', 'action': 'hijack-dns'},
      ],
      'final': vpnConfig.outbounds.first['tag'],
    },
  };
}
```

### 3.6 Запуск/остановка VPN

**MethodChannel `teremok/vpn`:**

```dart
// lib/features/vpn/vpn_provider.dart
class VpnController {
  static const _channel = MethodChannel('teremok/vpn');

  Future<void> start(Map<String, dynamic> singBoxConfig) async {
    final json = jsonEncode(singBoxConfig);
    try {
      await _channel.invokeMethod('start', {'config': json});
    } on PlatformException catch (e) {
      throw VpnStartException(e.message ?? 'Unknown VPN start error');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException catch (e) {
      throw VpnStopException(e.message ?? 'Unknown VPN stop error');
    }
  }

  Stream<VpnState> get stateStream => _channel
      .invokeMethod('getState')
      .asStream()
      .map((s) => VpnState.values.firstWhere((e) => e.name == s));
}
```

**Android-сторона (`TeremokVpnService.kt`):**

```kotlin
class TeremokVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var singBoxRunner: SingBoxRunner? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val configJson = intent?.getStringExtra("config") ?: return START_NOT_STICKY
        
        // Запустить foreground notification (обязательно для Android 8+)
        startForeground(
            NOTIFICATION_ID,
            buildNotification("Teremok Connect подключается...")
        )
        
        val builder = Builder()
            .setSession("Teremok Connect")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .setMtu(1500)
        
        tunInterface = builder.establish() ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Передаём tun FD в sing-box через JNI
        singBoxRunner = SingBoxRunner()
        singBoxRunner?.start(configJson, tunInterface!!.fd)
        
        return START_STICKY
    }

    override fun onRevoke() {
        singBoxRunner?.stop()
        tunInterface?.close()
        stopSelf()
    }

    override fun onDestroy() {
        singBoxRunner?.stop()
        tunInterface?.close()
        super.onDestroy()
    }
}
```

**Когда юзер нажимает Connect:**

```dart
// lib/features/vpn/vpn_provider.dart (Riverpod Notifier)
class VpnNotifier extends Notifier<VpnState> {
  @override
  VpnState build() => VpnState.disconnected;

  Future<void> connect() async {
    state = VpnState.connecting;
    try {
      // 1. Запросить разрешение на VPN (Android)
      final intent = await _channel.invokeMethod<String>('prepareVpn');
      if (intent != null) {
        // Система покажет диалог "Разрешить VPN"
        final granted = await _channel.invokeMethod<bool>(
          'requestVpnPermission',
          {'intent': intent},
        );
        if (!granted) {
          state = VpnState.error;
          return;
        }
      }

      // 2. Получить конфиг
      final config = await ref.read(vpnRepositoryProvider).fetchConfig();
      final singBoxConfig = buildSingBoxConfig(config);

      // 3. Запустить
      await _controller.start(singBoxConfig);
      state = VpnState.connected;
    } catch (e) {
      state = VpnState.error;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    state = VpnState.disconnecting;
    try {
      await _controller.stop();
      state = VpnState.disconnected;
    } catch (e) {
      state = VpnState.error;
      rethrow;
    }
  }
}
```

### 3.7 UI: экраны и состояния

**Экраны:**

1. **LoginScreen** (`lib/features/auth/ui/login_screen.dart`)
   - Логотип "Teremok Connect"
   - TextField с маской `+7 (XXX) XXX-XX-XX`
   - Кнопка "Получить звонок" (CTA)
   - Snackbar при ошибке
   - Ссылка на смену языка (RU/EN)

2. **VerifyScreen** (`lib/features/auth/ui/verify_screen.dart`)
   - Заголовок "Введите последние 4 цифры"
   - Пин-пад из 4 ячеек (Material 3 OutlinedInput)
   - Auto-submit при заполнении
   - Кнопка "Назад" → LoginScreen
   - Таймер обратного отсчёта 60 сек для повторного звонка

3. **HomeScreen** (`lib/features/home/ui/home_screen.dart`)
   - AppBar с overflow menu (Settings, Logout, Language)
   - Большой круглый индикатор (диаметр ~200dp):
     - Отключено: серый, текст "Отключено"
     - Подключение: жёлтый + спиннер
     - Подключено: зелёный + галочка
     - Ошибка: красный + крестик
   - Большая кнопка Connect/Disconnect (меняет label)
   - Subtitle: "Трафик зашифрован" / "Трафик не защищён"

**Состояния (Riverpod):**

```dart
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
final vpnProvider = NotifierProvider<VpnNotifier, VpnState>(VpnNotifier.new);
final languageProvider = NotifierProvider<LanguageNotifier, Locale>(LanguageNotifier.new);
final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
```

---

## 4. Тестирование без симулятора (на реальном Android через ADB)

### 4.1 Установка APK

```bash
# Собрать debug APK
cd ~/teremok-connect/mobile
flutter build apk --debug

# Установить на подключённый по USB телефон
adb devices  # проверить, что устройство видно
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`-r` = переустановить, если уже стоит. Без `-r` будет ошибка `INSTALL_FAILED_ALREADY_EXISTS`.

Для быстрой разработки лучше использовать `flutter run`:
```bash
flutter run -d <device-id>
# или если устройство одно:
flutter run
```

Hot reload: `r` в терминале. Hot restart: `R`.

### 4.2 Просмотр логов

```bash
# Только Flutter-логи (наш print, debugPrint, dart:developer log)
adb logcat | grep -i flutter

# С цветом и более читаемо
adb logcat -v color | grep -iE 'flutter|teremok'

# Только ошибки
adb logcat *:E | grep -i flutter

# Очистить буфер перед тестом
adb logcat -c
```

В коде используй `developer.log()` или `debugPrint()` — они попадают в logcat с тегом `flutter`.

### 4.3 Тестирование против локального backend

Backend крутится на `localhost:8000` на твоей машине. Телефон через USB не имеет доступа к localhost — нужен `adb reverse`:

```bash
# Маппит порт 8000 на телефоне → 8000 на хосте
adb reverse tcp:8000 tcp:8000

# Проверить
adb reverse --list
# Ожидаемо: (reverse) tcp:8000 tcp:8000
```

После этого в приложении baseUrl = `http://localhost:8000` — и телефон пойдёт на твой комп через USB.

**⚠️ Для Android с API 28+ нужно добавить в `AndroidManifest.xml`:**

```xml
<application ... android:usesCleartextTraffic="true">
```

Иначе HTTP (не HTTPS) будет блокироваться. Для production — выпустить TLS-сертификат и убрать этот флаг.

### 4.4 Проверка VPN после подключения

```bash
# На телефоне после Connect должен появиться VPN-интерфейс
adb shell ifconfig  # ищем tun0 или подобное

# Проверить, что трафик идёт через VPN
adb shell ping -c 3 8.8.8.8  # должен работать
adb shell curl -s https://api.ipify.org  # должен показать IP нашего сервера, а не провайдера
```

---

## 5. CI/CD (минимальный, чтобы сразу запустить)

### 5.1 GitHub Actions для Android

Файл `.github/workflows/mobile-android.yml`:

```yaml
name: Mobile Android Build

on:
  push:
    branches: [main, 'feat/mobile-*', 'fix/mobile-*']
    paths: ['mobile/**']
  pull_request:
    paths: ['mobile/**']

jobs:
  build-android:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.5'
          channel: stable

      - name: Install dependencies
        working-directory: mobile
        run: flutter pub get

      - name: Analyze
        working-directory: mobile
        run: flutter analyze

      - name: Run tests
        working-directory: mobile
        run: flutter test

      - name: Build debug APK
        working-directory: mobile
        run: flutter build apk --debug

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: android-debug-apk
          path: mobile/build/app/outputs/flutter-apk/app-debug.apk
          retention-days: 7

  build-android-release:
    runs-on: ubuntu-latest
    needs: build-android
    if: github.ref == 'refs/heads/main'
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.5'
          channel: stable

      - name: Setup Java for signing
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Decode keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > mobile/android/app/keystore.jks

      - name: Build release APK
        working-directory: mobile
        run: flutter build apk --release --split-per-abi
        env:
          KEYSTORE_PATH: android/app/keystore.jks
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}

      - name: Upload release APKs
        uses: actions/upload-artifact@v4
        with:
          name: android-release-apk
          path: |
            mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
            mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
            mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk
```

**Секреты для настройки** (один раз через GitHub UI → Settings → Secrets):
- `ANDROID_KEYSTORE_BASE64` — `base64 -w 0 keystore.jks`
- `KEYSTORE_PASSWORD` — пароль от keystore
- `KEY_ALIAS` — alias ключа (обычно `upload`)
- `KEY_PASSWORD` — пароль от ключа

### 5.2 Codemagic для iOS (вкратце)

Регистрация на [codemagic.io](https://codemagic.io), подключить GitHub-репо.

Минимальный `codemagic.yaml`:

```yaml
workflows:
  ios-release:
    name: iOS Release
    max_build_duration: 60
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    scripts:
      - name: Get packages
        script: cd mobile && flutter pub get
      - name: Build iOS (no codesign)
        script: cd mobile && flutter build ios --release --no-codesign
    artifacts:
      - mobile/build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        # Настраивается отдельно в UI Codemagic
```

TestFlight upload — настраивается через UI Codemagic → Publishing → App Store Connect → ввести API Key.

---

## 6. Типичные подводные камни

### 6.1 sing-box binding: выбираем подход

**Вариант A: Go-Flutter FFI bridge** (рекомендую)
- ✅ Полный контроль, минимум overhead
- ❌ Сложно настроить CGO, долгая первая сборка (~15 мин)
- **Когда выбирать:** если планируем глубокие фичи (kill-switch, custom routing)

**Вариант B: sing-box как AAR + JNI обёртка** (рекомендую для MVP)
- ✅ Проще, sing-box официально собирается под Android
- ✅ Быстрая сборка, предсказуемый размер APK (+~15 МБ)
- ❌ Меньше гибкости, но для MVP хватит
- **Когда выбирать:** если хочется быстрее дойти до рабочего VPN

**Вариант C: subprocess sing-box binary**
- ❌ Плохо: бинарь лежит в `/data/local/tmp/`, требует root на старых Android
- ❌ UX-кошмар: foreground notification от sing-box, не от нашего приложения
- **Не рекомендую** — забудь этот вариант

**Моя рекомендация: B.** Скачиваем sing-box-android-arm64-v8a.aar с GitHub releases SagerNet/sing-box, кладём в `mobile/android/app/libs/`, подключаем в `build.gradle`. Пишем Kotlin-обёртку `SingBoxRunner.kt`, которая загружает нативную библиотеку и предоставляет методы `start(configJson, tunFd)` / `stop()`.

**План Б (если AAR не заводится):** FFI через dart:ffi + sing-box.so (C-ABI). Sing-box имеет C-бинддинги, но они экспериментальные. Потребует компиляции sing-box из исходников через Android NDK.

### 6.2 Android `VpnService` permission в runtime

**Неочевидно:** даже если в манифесте указан `BIND_VPN_SERVICE`, при первом запуске Android показывает **системный диалог** "Приложение Teremok Connect запрашивает разрешение на VPN. Разрешить?". Юзер должен нажать "ОК".

**Обработка:**

```kotlin
// В MainActivity.kt
private val vpnPermissionLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode == RESULT_OK) {
        // Юзер разрешил — стартуем VPN service
        startVpnService()
    } else {
        // Отказал — показываем snackbar
        showVpnDeniedSnackbar()
    }
}

fun prepareVpn() {
    val intent = VpnService.prepare(this)
    if (intent != null) {
        vpnPermissionLauncher.launch(intent)
    } else {
        // Уже разрешено (повторный запуск)
        startVpnService()
    }
}
```

### 6.3 iOS Network Extension

**Боль:** provisioning profile должен содержать capability `com.apple.developer.networking.networkextension`. Apple проверяет это вручную при регистрации Apple Developer аккаунта (1-3 рабочих дня). Включается в Xcode → Capabilities → Network Extensions → Personal VPN.

**Код:** нужен `NEVPNManager` или `NEPacketTunnelProvider`. Это **отдельный Swift extension** в `ios/Runner/VpnTunnelProvider/`. Flutter общается с ним через App Groups (UserDefaults suite) — общий конфиг для app и extension.

**Рекомендую отложить iOS на потом** — сначала Android MVP, потом iOS через Codemagic.

### 6.4 JWT refresh race conditions

**Проблема:** два запроса одновременно получают 401 → оба шлют refresh → один из refresh становится невалидным (если backend инвалидирует старые refresh после использования).

**Решение:** мьютекс в interceptor (см. код выше) — пока один refresh идёт, остальные ждут.

**На backend (Task #0):** если хочешь настоящий single-use refresh — добавь таблицу `refresh_tokens(id, user_id, token_hash, used_at, expires_at)`. Каждый refresh помечает старый как used. Если кто-то пытается использовать used refresh — 401, force re-login.

Для MVP достаточно **rotating refresh без инвалидации** — каждый refresh выдаёт новую пару, старый refresh продолжает работать до истечения 7 дней. Менее безопасно, но проще.

### 6.5 Foreground service убивается Android

**Симптом:** через 30-60 сек после Connect приложение показывает "VPN остановлен", хотя система говорит, что VPN активен.

**Причина:** Android 12+ агрессивно убивает background-сервисы. VPN-сервис **обязан** вызвать `startForeground()` в течение 5 секунд после `onStartCommand()`.

**Решение:**
```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Teremok Connect")
        .setContentText("VPN активен")
        .setSmallIcon(R.drawable.ic_vpn)
        .setOngoing(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .build()
    
    startForeground(NOTIFICATION_ID, notification)
    // ... остальная логика
}
```

Канал `CHANNEL_ID` должен быть создан заранее в `Application.onCreate()`.

### 6.6 Прочие грабли

| Проблема | Симптом | Решение |
|----------|---------|---------|
| `flutter build apk` падает с NDK error | "NDK not configured" | Установить Android NDK через SDK Manager, добавить `ndkVersion` в `app/build.gradle` |
| HTTP трафик блокируется | "Cleartext HTTP traffic not permitted" | `android:usesCleartextTraffic="true"` в manifest (только для dev!) |
| Flutter не видит устройство | `adb devices` пуст | Включить "USB debugging" в Developer Options на телефоне, сменить USB-кабель (дешёвые не передают данные) |
| Токены теряются между запусками | После перезапуска снова логин-скрин | Проверить, что `flutter_secure_storage` записывает — добавить `logger` после `save()` |
| VPN подключается, но трафик не идёт | `ping 8.8.8.8` timeout | Проверить `auto_route: true` и `strict_route: true` в sing-box config; проверить что `addRoute("0.0.0.0", 0)` в Android Builder |
| `kotlin-android` plugin не найден | Gradle error | В `android/settings.gradle` добавить `pluginManagement { plugins { id "org.jetbrains.kotlin.android" version "1.9.0" } }` |

---

## 7. Готовые команды для копипаста в Cursor

Эти команды копируешь по одной в Cursor. После каждой — Cursor генерирует код, ты проверяешь.

### Команда 1: Создать Flutter-проект в существующей директории

```bash
cd ~/teremok-connect
flutter create --org com.teremok --project-name teremok_connect --platforms android mobile
```

### Команда 2: Настроить pubspec.yaml

> "Замени содержимое `mobile/pubspec.yaml` на версии из секции 2.1 этого плана. Затем запусти `flutter pub get` через терминал."

### Команда 3: Создать структуру lib/

> "Создай следующую структуру папок в `mobile/lib/`: `core/config/`, `core/theme/`, `core/errors/`, `core/utils/`, `features/auth/data/`, `features/auth/ui/`, `features/home/ui/`, `features/vpn/data/`, `features/vpn/domain/`, `infrastructure/network/`, `infrastructure/storage/`, `l10n/`. В каждой папке создай пустой `.gitkeep` файл."

### Команда 4: Минимальный main.dart

> "Создай `mobile/lib/main.dart` с минимальным MaterialApp, текстом 'Hello Teremok' по центру экрана, primary color `Color(0xFF1A73E8)` (Material Blue). Без роутинга пока."

### Команда 5: Проверить что всё запускается

```bash
cd ~/teremok-connect/mobile
flutter run -d <device-id>
```

На экране телефона должен появиться "Hello Teremok".

---

## 8. Чеклист для вайбкодера

Перед началом каждой сессии:
- [ ] `adb devices` — телефон виден
- [ ] `adb reverse --list` — `tcp:8000 tcp:8000` в списке (если тестируем с локальным backend)
- [ ] Backend запущен: `curl http://localhost:8000/health`
- [ ] Cursor открыт на `~/teremok-connect/mobile/`

После каждой задачи:
- [ ] `flutter analyze` — без ошибок
- [ ] `flutter test` — все тесты зелёные (если есть)
- [ ] `flutter run` — приложение запускается
- [ ] Проверить acceptance criteria конкретной задачи
- [ ] `git add -A && git commit -m "feat(mobile): <описание из таблицы выше>"`

---

## 9. Что делать, если Cursor застрял

1. **Скопировать ошибку** из терминала → вставить в Cursor → попросить "объясни и исправь".
2. **Если Cursor галлюцинирует** (предлагает несуществующие API): дать ему конкретную ссылку на pub.dev или GitHub и сказать "используй именно эту версию".
3. **Если две попытки не помогли** — откатить через `git checkout -- .` и переформулировать задачу проще. Разбей на 2-3 подзадачи.
4. **Если совсем плохо** — напиши мне (Hermes), приложив: что пытался, что Cursor выдал, лог из `flutter run`. Я дам более точный план.

---

## Резюме

Этот план покрывает MVP Android-клиента для Teremok Connect: от пустой директории `mobile/` до рабочего VPN-приложения, устанавливаемого через `adb install`. 20 задач, ~25-30 часов, ~2-3 недели в ритме вайбкодера.

**Критические решения, которые ты должен принять сейчас:**

1. ✅ Добавить `POST /auth/refresh` в backend (Task #0) — настоятельно рекомендую.
2. ✅ Выбрать sing-box binding: **вариант B (AAR + JNI)** — рекомендую для скорости.
3. ✅ Не делать iOS пока — сосредоточиться на Android MVP.
4. ✅ Не делать desktop пока — даже P1 Windows/macOS отложить.

Если согласен — начинай с Task #0 (backend refresh endpoint), потом Task #1 (flutter create). Если есть вопросы по конкретной задаче — спрашивай.