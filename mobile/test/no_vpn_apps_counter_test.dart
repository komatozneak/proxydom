import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/widgets/app_icon.dart';
import 'package:teremok_connect/features/settings/data/installed_apps_channel.dart';

void main() {
  group('noVpnAppsCounter', () {
    test('counts only disallowed packages that are still installed', () {
      final counter = noVpnAppsCounter(
        launcherPackages: const [
          'com.a',
          'com.b',
          'com.c',
        ],
        disallowedPackages: {'com.a', 'com.gone', 'com.b'},
      );
      expect(counter.enabled, 2);
      expect(counter.total, 3);
    });

    test('empty inventory → 0 / 0', () {
      final counter = noVpnAppsCounter(
        launcherPackages: const [],
        disallowedPackages: {'com.a'},
      );
      expect(counter.enabled, 0);
      expect(counter.total, 0);
    });
  });

  group('iconForOsnovnyeCategory', () {
    test('returns VK launcher icon only', () {
      final typed = <String, Uint8List>{
        'com.vkontakte.android': Uint8List.fromList([1, 2, 3]),
        'ru.ozon.app.android': Uint8List.fromList([4, 5, 6]),
      };
      expect(iconForOsnovnyeCategory('vk', typed), isNotNull);
      expect(iconForOsnovnyeCategory('ru', typed), isNull);
      expect(iconForOsnovnyeCategory('ozon', typed), isNull);
      expect(kOsnovnyeIconPackages.keys, ['vk']);
    });
  });

  group('osnovnyeCategoryIcon', () {
    test('maps non-VK categories to AppIcons; vk is null', () {
      expect(osnovnyeCategoryIcon('vk'), isNull);
      expect(osnovnyeCategoryIcon('ru'), AppIcons.osnovnyeRu);
      expect(osnovnyeCategoryIcon('gov'), AppIcons.osnovnyeGov);
      expect(osnovnyeCategoryIcon('tiktok'), AppIcons.osnovnyeTiktok);
      expect(osnovnyeCategoryIcon('yandex'), AppIcons.osnovnyeYandex);
      expect(osnovnyeCategoryIcon('ozon'), AppIcons.osnovnyeOzon);
      expect(osnovnyeCategoryIcon('wb'), AppIcons.osnovnyeWb);
      expect(osnovnyeCategoryIcon('unknown'), isNull);
    });
  });
}
