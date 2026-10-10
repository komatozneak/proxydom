# mobile/scripts — вспомогательные скрипты

Два скрипта, оба запускаются из каталога `mobile/`.

## fetch-goog-cidrs.ps1

Обновляет список адресов Google/YouTube, которые уходят в прокси всегда.

```powershell
cd mobile
.\scripts\fetch-goog-cidrs.ps1
```

Берёт официальный `https://www.gstatic.com/ipranges/goog.json` — публичный
список префиксов Google — и пишет `mobile/assets/rules/youtube-google.cidr`
с датой и `sync-token` в шапке. Чужие списки (`youtube.txt`, `google.txt` из
сторонних репозиториев) не копируем: источник должен быть первоисточником,
иначе список нельзя перепроверить.

Файл попадает в сборку, поэтому после обновления проверьте диф: список влияет
на маршрутизацию, а не только на косметику.

## fetch-trusttunnel-aar.ps1

Скачивает `trusttunnel-client-android` в `android/app/libs/`.

```powershell
$env:GPR_KEY = "<PAT с read:packages>"
cd mobile
.\scripts\fetch-trusttunnel-aar.ps1
```

Пакет лежит только в GitHub Packages у `TrustTunnel/TrustTunnelClient` — в Maven
Central его нет, а сборка из исходников требует Conan + CMake + NDK. Нужен
GitHub PAT со скоупом `read:packages`: токен `gh` из keyring его обычно не имеет
и отдаёт 401.

Версия закреплена (`1.1.5-rc.2`); другая версия печатает предупреждение и
требует решения owner. Скачанный файл меньше 1 МБ считается битым и удаляется.
Артефакт **не** на Gradle classpath — подробности в
[`android/app/libs/README.md`](../android/app/libs/README.md).

## Чего здесь нет

Скриптов сборки VPN-ядра в этом каталоге нет намеренно. Клиент собирается
только из permissive-лицензий, а `libbox`/`sing-box` — GPL-3.0, который в
поставку не входит: §10 запрещает дополнительные ограничения, §12 запрещает
распространять несовместимое произведение, и условия App Store — ровно такое
ограничение. Поэтому и скрипта, и архива в дереве нет. Движок — `hy2bind`
(`v2fly/v2ray-core`, MIT), его сборка описана в
[`android/hysteria-bind/`](../android/hysteria-bind/).
