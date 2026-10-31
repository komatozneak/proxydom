# ProxyDom: аудит Private-перехода и публикации в сторы

Дата: 2026-10-31. Ветка: `feat/reality-engine-and-agent-workflow`.
Область: `mobile/` (Flutter + Kotlin + Go), `desktop/windows/`, `.github/`,
`docs/`, `scripts/`.

> Важно: переименование UI не меняет техническую классификацию приложения.
> Android-сборка использует `VpnService`, iOS — Packet Tunnel Provider. В Play
> Console и App Store Connect эти декларации всё равно заполняются правдиво;
> ниже проверено именно то, что можно проверить кодом и сборкой.

## 1. Найденные триггеры и что с ними сделано

| № | Триггер | Где | Действие | Статус |
|---|---|---|---|---|
| 1 | Радужный флаг в наборе стран | `mobile/assets/flags/lgbt.svg` | удалён; ссылок в коде не было | готово |
| 2 | Логотипы YouTube / Claude | `mobile/assets/brand/sites/youtube.png`, `claude.png` | папка `sites/` удалена; запись в `pubspec.yaml` убрана | готово |
| 3 | Брендовая иллюстрация поддержки | `mobile/assets/brand/connect/teremok-headphones.png` | переименована в `support-headphones.png`; в поставку не входит (на неё не было ссылок) | готово |
| 4 | Логотипы сервисов в наборе иконок | `mobile/lib/core/widgets/app_icon.dart` | YouTube/TikTok/Instagram/Discord/Telegram/Claude/ChatGPT-константы удалены; добавлены нейтральные `categoryMedia/Cloud/Work/Backup` | готово |
| 5 | Красный цвет YouTube | `AppBrand.youtubePlay`, `server_glyph.dart` | константа удалена, плитки категорий нейтральные | готово |
| 6 | YouTube-плитка и gamepad-эмодзи в карточке узла | `pool_server_mark.dart`, `server_glyph.dart` | нейтральные иконки «Медиа-поток», «Облачный API», «Рабочий узел», «Резервный канал» | готово |
| 7 | Брендовые названия в UI-локализации | 45 ключей в `app_ru.arb` / `app_en.arb` | VPN → туннель / защищённый маршрут / прокси-соединение | готово |
| 8 | «Белые списки» | `homeNoVpnRow`, `settingsNoVpn`, `settingsNoVpnHint` | «Маршрутизация» / «Правила раздельного туннеля» | готово |
| 9 | Платные подписки и автопродление в l10n | 20 ключей `settingsSubscription*`, `settingsAccess*`, `lockedPlan*`, `restorePayment*` | удалены как мёртвые; в коде не использовались | готово |
| 10 | Ozon/Wildberries/Госуслуги в тексте режима | `modesConfirmFullBody` | заменено на нейтральные «внутренние сервисы и российские ресурсы» | готово |
| 11 | Зарубежные примеры в пустых состояниях | `freeFoundEmpty`, `freeOnboardBody`, `pcOnboardBody`, `splitTunnelDomainHint` | Москва / Санкт-Петербург / Новосибирск / `gw.company-net.ru` | готово |
| 12 | VPN в шторке Android | `ShadeNotification.kt`, `strings.xml` | «Активен защищенный маршрут», «Настройки туннеля»; каналы переименованы | готово |
| 13 | `teremok_*` legacy-каналы | `ShadeNotification.kt` | список удалён | готово |
| 14 | VPN в ошибках Dart/Kotlin | `vpn_connect_error.dart`, `vpn_provider.dart`, `MainActivity.kt`, `ProxyDomVpnService.kt` | `Native tunnel error`, `Tunnel permission denied`, `Tunnel was revoked…` | готово |
| 15 | Ссылка `teremok://` | `AndroidManifest.xml`, `Info.plist`, `hy2_link_parser.dart` | схема и парсинг удалены | готово |
| 16 | Захардкоженный force-proxy YouTube/Google | `vpn_route_policy.dart`, `hy2bind_split.go` | встроенный список удалён; остался только динамический `force_proxy_domains` из подписки | готово |
| 17 | Захардкоженные домены заблокированных сервисов | `split_tunnel_prefs.dart` | `kSplitTunnelDomainAliases` и `kSplitTunnelProxyIpCidrs` удалены | готово |
| 18 | Категория TikTok | `kOsnovnyeCategories`, миграция `kTunnelOnly*` | удалена вместе с one-shot миграцией и иконкой | готово |
| 19 | `incy` в комментариях/доках | `share_link_parser.dart`, `docs/parity/*` | документ переписан в `standard-intake-parity.md`, упоминания бренда убраны | готово |
| 20 | `DoDoVPN` в комментариях | `country_flags.dart`, `subscription_label.dart` | заменено на `CompanyNet` | готово |
| 21 | Брендовое имя JKS | `play-build.ps1`, `build-sideload.ps1`, `key.properties.template`, `export-upload-cert.ps1` | скрипты читают `storeFile` из `key.properties`; имя файла больше не зашито | готово |
| 22 | Широкий `-keep com.proxydom.app.**` | `proguard-rules.pro` | оставлены только manifest-entry points, Flutter, `HysteriaBridge`, gomobile | готово |
| 23 | Debug-активити в release | `DebugVpnActivity.kt` | перенесена в `src/debug/kotlin` | готово |
| 24 | logcat с IP/доменами в release | `NativeLog.kt`, `CoreLog.kt` | logcat только при `BuildConfig.DEBUG`; core log по умолчанию `warn` | готово |
| 25 | Go-бинарники с символами и build path | `build-aar.sh`, `build-ios.sh`, `build-msi.ps1` | `-trimpath -ldflags="-s -w -buildid="` | готово |
| 26 | Пути сборочной машины в AAR | `namespace_aar.py` | `_scrub_source_paths` + проверка в `_verify`; AAR проверен | готово |
| 27 | Flutter AOT без обфускации | `android-apk.yml`, `ios-testflight.yml`, `build-sideload.ps1`, `play-build.ps1` | `--obfuscate --split-debug-info=build/symbols`; для iOS — env `DART_OBFUSCATION/SPLIT_DEBUG_INFO` | готово |
| 28 | Символы в релизных архивах | `.gitignore`, workflows | `build/symbols/` игнорируется; iOS/Android выгружают symbols отдельным артефактом | готово |
| 29 | Слабые лицензионные гварды | `license_guard_test.go`, `check-payload-licenses.ps1` | добавлены запрещённые префиксы `sagernet`, `xray-core`, `libbox`; тест Windows-guard обновлён | готово |
| 30 | MPL-2.0 без пояснения об источнике | `third_party_notices_test.go` | условная секция «MPL-2.0 components» с указанием апстрима | готово |
| 31 | Прямые ссылки на GitHub в клиенте | `mobile/lib`, `.github` | не найдены; updater ходит на `api.proxydom.su` | проверено |
| 32 | Публичная витрина релизов | `scripts/release-publisher/` | новый publisher: только бинарники + `RELEASE.json` + SHA256 | готово |
| 33 | 277 неиспользуемых l10n-ключей в бинарнике | `app_ru.arb`, `app_en.arb` | удалены: аккаунт, устройства, лимиты, «Оплата в приложении недоступна», `−{percent}%`, реферальные «дни после оплаты», «Тёплый дом в холодном интернете» | готово |
| 34 | Диагностический отчёт целиком в logcat в release | `diagnostics_service.dart` | `debugPrint` не вырезается из release; дамп теперь только при `kDebugMode`, отчёт остаётся в файле | готово |
| 35 | Windows-окно без обфускации Dart | `build-msi.ps1` | `flutter build windows --release --obfuscate --split-debug-info=build/symbols` | готово |
| 36 | Нет CI-гейта лицензий Dart-графа | `mobile/test/dependency_license_guard_test.dart` | тест обходит `.dart_tool/package_config.json`, валит GPL/LGPL/AGPL/SSPL/EUPL, вырезает MPL-определение Secondary License | готово |

## 2. Что изменено по шагам

### Шаг 1. Ассеты и бренды

- Удалены `lgbt.svg`, `sites/youtube.png`, `sites/claude.png`, папка `sites/`.
- `teremok-headphones.png` → `support-headphones.png`; файл не был подключён
  в `pubspec.yaml`, поэтому в APK/IPA/MSI он не попадал и не попадает.
- Иконки сервисов заменены нейтральными категориями; старые ключи
  `youtube`/`gaming` в сохранённых данных читаются как `media`/`cloud`.
- `docs/parity/incy-intake-parity.md` заменён на
  `docs/parity/standard-intake-parity.md`; ссылка в `AGENTS.md` обновлена.
- В `docs/guide`, `README.md` и продакшен-коде упоминаний `incy`, `teremok`,
  `dodo` не осталось.

### Шаг 2. Терминология

- RU/EN ARB: 45 значений переписаны, 20 мёртвых платёжных ключей удалены.
- Android: строки шторки, канала уведомлений, быстрых настроек.
- Dart: ошибки подключения, конфликт туннеля, подсказки разрешения.
- OS-путь `Настройки → VPN` оставлен как системный ярлык: это название
  системного экрана, а не продуктовая формулировка. Заменять его на
  несуществующий «Сеть → Туннель» нельзя без поломки инструкции.
- «Антиглушилка», «Обход», «Обход DPI», «Разблокировка» в продакшен-коде
  не встречаются. Технических TLS-fragmentation-настроек в UI не было.

### Шаг 3. Витрина

- `profileNotice()`/`SubscriptionNotice` уже были динамическими: текст и
  support-URL приходят из заголовков/тела подписки.
- `locations_screen.dart` рисует кнопку только при непустом `planeUrl`;
  `server_instrument.dart` — только при непустом `onTelegram`.
- В базовой сборке нет зашитых `t.me`, ботов, тарифов, «VIP» и кнопок оплаты.
- Тест `a link without an announcement leaves the slot empty` фиксирует
  пустую карточку для обычного ключа/подписки без метаданных.

### Шаг 4. Маршрутизация

- Удалены встроенные списки заблокированных сервисов:
  `kSmartProxyForceSuffixes`, `kSplitTunnelDomainAliases`,
  `kSplitTunnelProxyIpCidrs`, TikTok-категория, YouTube/Google force-proxy
  в Go.
- Остались технические пресеты: LAN/private (в движке), российские ресурсы
  напрямую, весь остальной трафик — через узел.
- Динамические `force_proxy_domains` из подписки по-прежнему поддерживаются
  движком; это единственный путь для расширенных списков.

### Шаг 5. Ресурсы и метаданные

- `ic_qs_vpn.png` → `ic_qs_tunnel.png` во всех плотностях; ссылки в манифесте,
  `ProxyDomTileService`, `QsTilePrompter` обновлены.
- `pubspec.yaml`: `Corporate proxy & network tunnel configuration client`.
- `Product.wxs`: описание MSI `Corporate proxy & network tunnel configuration client`.
- `NSLocalNetworkUsageDescription`: формулировка про корпоративный прокси и
  проверку задержки.
- `BIND_VPN_SERVICE`, `android.net.VpnService`, `ProxyDomVpnService` не тронуты.

### Шаг 6. Лицензии

- Go-гвард проверяет граф всех трёх целей (Android/iOS/Windows) и валит
  `github.com/sagernet/*`, `github.com/xtls/xray-core`, `github.com/libbox/*`.
- `pubspec.lock` / resolved Dart-граф (126 пакетов): 21 MIT, 8 Apache-2.0,
  92 BSD, 1 MPL-2.0 (`gtk`, только Linux-плагин). GPL/AGPL/SSPL нет.
  `sky_engine` — заглушка Flutter-движка (BSD-3); её длинный LICENSE содержит
  тексты сторонних компонентов, а не отдельную copyleft-зависимость.
- Windows-гвард ищет те же маркеры в сырых бинарниках; self-test 10/10.
- В `third_party_notices_test.go` добавлена условная MPL-2.0-секция:
  неизменённые MPL-модули сопровождаются ссылкой на апстрим, а не раскрытием
  кода ProxyDom.
- Экран «Лицензии открытого ПО» регистрирует Go-notices под именами
  `hy2bind`, `hysteria`, `quic-go`, `gvisor`, `v2ray-core` (Xray в сборку не
  входит и в notices не заявляется).

### Шаг 7. Обфускация

- Go: `-trimpath -ldflags="-s -w -buildid="` в AAR, XCFramework и Windows exe.
- Flutter: `--obfuscate --split-debug-info=build/symbols` в release-сборках;
  iOS получает те же значения через `DART_OBFUSCATION`/`SPLIT_DEBUG_INFO`.
- R8: `isMinifyEnabled = true`, `isShrinkResources = true`; узкие `-keep`.
  В release-mapping `com.proxydom.app.session.VpnSessionEngine -> n3.E`,
  `PathHealth -> n3.k`; `DebugVpnActivity` и `com/proxydom/app/session` в DEX
  отсутствуют, а `ProxyDomVpnService`, `HysteriaBridge`, `ProxyDomTileService`,
  `VpnActionReceiver`, `hy2bind` сохранены.
- `DebugVpnActivity` физически отсутствует в release-варианте.
- logcat — только debug; core log в release по умолчанию `warn`, а
  `TunnelLogLevel.recordingLevel` в release не опускается ниже `warn`, если
  пользователь явно не выбрал `debug`.
- AAR проверен: в `libhyjni.so` нет `C:\Users`, имени владельца, `www`-путей,
  `gomobile-work`; `.symtab`/`.debug_*` вырезаны.
- Windows exe проверен: нет `C:\Users`, `.debug_info`; модуль больше не
  содержит GitHub-хэндл владельца.

### Шаг 8. Private / public

- В клиенте и workflows нет обращений к GitHub API или к исходному репозиторию;
  updater использует `api.proxydom.su`.
- `scripts/release-publisher/publish-release.ps1` принимает только
  `.apk/.aab/.ipa/.msi/.exe/.dmg`, отказывается от `debug/ci/symbols/unsigned`,
  считает SHA256, пишет `RELEASE.json` и коммитит только `releases/<version>/`.
- Smoke-тест publisher: два артефакта, SHA256, `RELEASE.json`, коммит — ок.

## 3. Проверки

| Проверка | Команда | Результат |
|---|---|---|
| Go-граф | `go mod tidy -diff` | чисто |
| Go-тесты | `go test ./...` | pass |
| AAR | `bash build-aar.sh` (Git Bash) | собран, `TestLocalAARMatchesTheSource` pass |
| AAR paths | `llvm-readelf` + raw scan | нет `C:\Users`, владельца, `.debug_*` |
| Windows exe | `go build -trimpath -ldflags "-s -w -buildid="` | нет `C:\Users`, `.debug_info` |
| Flutter analyze | `flutter analyze --no-fatal-infos` | 26 issues, все — прежние style-infos; 0 errors |
| Flutter tests | `flutter test --dart-define=AUTH_ANONYMOUS=false` | 496 pass (включая `dependency_license_guard_test.dart`: 126 пакетов) |
| License self-test | `test-check-payload-licenses.ps1` | 10/10 |
| C++ | `protocol_test.exe`, `supervisor_test.exe` | ok |
| Kotlin | `gradlew :app:testDebugUnitTest` | BUILD SUCCESSFUL |
| Release R8 | `gradlew :app:assembleRelease` | BUILD SUCCESSFUL |
| Release APK | `aapt dump badging/resources`, zip scan | `com.proxy.dom`, minSdk 26, `ic_qs_tunnel`, нет `teremok`, нет `DebugVpnActivity`, нет `brand/sites` и `flags/lgbt` |
| Obfuscated APK | `flutter build apk --release --obfuscate --split-debug-info=build/symbols` | 175.4 MB; symbols в `build/symbols`, в APK их нет |

## 4. Остаточные риски и ручные шаги

1. **Store declarations.** Приложение использует `VpnService` и Packet Tunnel
   Provider. В Google Play декларация VPN и `specialUse` FGS заполняются
   правдиво; переименование строк не отменяет эту обязанность. В Apple
   аналогично раскрывается Network Extension.
2. **iOS/Windows артефакты** не собраны на этой машине: iOS требует macOS и
   Xcode, MSI — WiX и подпись. Workflow/скрипты обновлены, но живая проверка
   на устройстве остаётся обязательной.
3. **Release R8** собран успешно; после него нужен smoke-тест на живом
   Android-устройстве (подключение, шторка, QS-тайл, split-tunnel).
4. **Локальный `key.properties`** может всё ещё указывать на старый
   `teremok-upload.jks`; скрипты теперь читают `storeFile` и работают с любым
   именем. Переименование самого JKS — на усмотрение владельца.
5. **Тестовые фикстуры** переименованы: `Teremok`/`DoDoVPN`/`teremokconnect`
   → `CompanyNet`/`company-net.ru`. Единственный остаток — имя старого
   Wintun-адаптера `teremokhy2` в `desktop/windows/service/protocol.cpp`:
   служба по нему находит и удаляет адаптер, оставленный старыми установками.
   Без него этот адаптер на обновлённых машинах считался бы чужим туннелем.
   Убирать — после того как старых установок не останется.
6. **MPL-2.0**: в текущем графе Go MPL-модулей нет; секция в notices появится
   автоматически, если зависимость с MPL-2.0 будет добавлена. В Dart-графе
   `gtk` (Linux-only) идёт под MPL-2.0, в мобильные/Windows-поставки не входит.
7. **Dart AOT и путь `.dart_tool`.** `--obfuscate` убирает имена, но
   `libapp.so` всё ещё содержит абсолютный URI сгенерированного
   `dart_plugin_registrant.dart` (`file:///…/.dart_tool/flutter_build/…`).
   Это поведение Flutter-тулинга, а не исходников. Go-бинарники и AAR уже
   очищены; для APK/IPA нужен либо нейтральный build-root в CI, либо
   пост-обработка `libapp.so` до подписи. Этот пункт нельзя закрыть только
   флагами `flutter build`.
8. **Слово `youtube`** убрано из продакшен-Dart: классификаторы имён
   строк, discovery плееров, комментарии. Строка, названная только «YouTube»,
   и сохранённый старой версией ключ `youtube` теперь получают глобус вместо
   «Медиа-поток»; `media`/`video`/`stream`/`медиа` по-прежнему дают категорию.
   В Go/Swift-комментариях упоминания остаются, в бинарник они не попадают.
9. **C++-тесты.** На этой машине `cmake --build` не находит заголовки MSVC
   (`cstddef`), поэтому прогнаны ранее собранные `protocol_test.exe` и
   `supervisor_test.exe` — они старше последнего коммита в
   `desktop/windows/service`. Актуальный прогон — джоба `windows-service` в CI.

## 5. Вердикт

Кодовая база готова к переводу в Private по пунктам 1–8: брендовые ассеты и
терминология вычищены, лицензионный гейт ужесточён, релизные флаги обфускации
добавлены, R8-правила сужены, сборка AAR проверена на отсутствие путей и
символов, publisher отделяет публичную витрину от исходников.

Одна оговорка по anti-RE: Dart AOT сохраняет URI
`dart_plugin_registrant.dart` (см. §4, п. 7). Go-часть и AAR закрыты полностью;
для APK/IPA этот путь нужно убрать нейтральным build-root в CI или
пост-обработкой до подписи. Это единственный известный остаток по путям сборки.

Публикация в сторы — **не автоматическая**: остаются декларации VpnService /
Network Extension, подпись, скриншоты, тестовый ключ и живой smoke-тест.
