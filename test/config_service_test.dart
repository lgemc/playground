import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:playground/services/config_service.dart';

void main() {
  late ConfigService configService;

  setUp(() async {
    configService = ConfigService.instance;
    await configService.initialize();

    // Clean up test data directories
    final globalDir = Directory('data/global');
    final testAppDir = Directory('data/test_app');
    if (await globalDir.exists()) {
      await globalDir.delete(recursive: true);
    }
    if (await testAppDir.exists()) {
      await testAppDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    // Clean up after tests
    final globalDir = Directory('data/global');
    final testAppDir = Directory('data/test_app');
    if (await globalDir.exists()) {
      await globalDir.delete(recursive: true);
    }
    if (await testAppDir.exists()) {
      await testAppDir.delete(recursive: true);
    }
  });

  group('ConfigService - Global Config', () {
    test('setDefault stores default value in memory', () {
      configService.setDefault('theme', 'dark');
      expect(configService.get('theme'), 'dark');
    });

    test('get returns default value when no override exists', () {
      configService.setDefault('language', 'en');
      expect(configService.get('language'), 'en');
    });

    test('set creates user override that takes precedence', () async {
      configService.setDefault('theme', 'dark');
      await configService.set('theme', 'light');
      expect(configService.get('theme'), 'light');
    });

    test('reset removes user override and reverts to default', () async {
      configService.setDefault('theme', 'dark');
      await configService.set('theme', 'light');
      await configService.reset('theme');
      expect(configService.get('theme'), 'dark');
    });

    test('delete removes both override and default', () async {
      configService.setDefault('theme', 'dark');
      await configService.set('theme', 'light');
      await configService.delete('theme');
      expect(configService.get('theme'), null);
    });

    test('isDefault returns true when using default value', () {
      configService.setDefault('theme', 'dark');
      expect(configService.isDefault('theme'), true);
    });

    test('isDefault returns false when using user override', () async {
      configService.setDefault('theme', 'dark');
      await configService.set('theme', 'light');
      expect(configService.isDefault('theme'), false);
    });

    test('getAll returns merged defaults and overrides', () async {
      configService.setDefault('theme', 'dark');
      configService.setDefault('language', 'en');
      await configService.set('theme', 'light');

      final all = configService.getAll();
      expect(all['theme'], 'light');
      expect(all['language'], 'en');
    });

    test('get with defaultValue fallback works', () {
      expect(configService.get('unknown', defaultValue: 'fallback'), 'fallback');
    });
  });

  group('ConfigService - App-Scoped Config', () {
    test('setDefault stores app-specific default', () {
      configService.setDefault('fontSize', '16', appId: 'test_app');
      expect(configService.get('fontSize', appId: 'test_app'), '16');
    });

    test('app-scoped configs are isolated', () {
      configService.setDefault('theme', 'dark', appId: 'app1');
      configService.setDefault('theme', 'light', appId: 'app2');

      expect(configService.get('theme', appId: 'app1'), 'dark');
      expect(configService.get('theme', appId: 'app2'), 'light');
    });

    test('set creates app-scoped user override', () async {
      configService.setDefault('fontSize', '14', appId: 'test_app');
      await configService.set('fontSize', '18', appId: 'test_app');
      expect(configService.get('fontSize', appId: 'test_app'), '18');
    });

    test('reset works for app-scoped config', () async {
      configService.setDefault('fontSize', '14', appId: 'test_app');
      await configService.set('fontSize', '18', appId: 'test_app');
      await configService.reset('fontSize', appId: 'test_app');
      expect(configService.get('fontSize', appId: 'test_app'), '14');
    });

    test('isDefault works for app-scoped config', () async {
      configService.setDefault('fontSize', '14', appId: 'test_app');
      expect(configService.isDefault('fontSize', appId: 'test_app'), true);

      await configService.set('fontSize', '18', appId: 'test_app');
      expect(configService.isDefault('fontSize', appId: 'test_app'), false);
    });

    test('getAll returns app-specific configs', () async {
      configService.setDefault('fontSize', '14', appId: 'test_app');
      configService.setDefault('theme', 'dark', appId: 'test_app');
      await configService.set('fontSize', '18', appId: 'test_app');

      final all = configService.getAll(appId: 'test_app');
      expect(all['fontSize'], '18');
      expect(all['theme'], 'dark');
    });
  });

  group('ConfigService - Persistence', () {
    test('global overrides persist to disk', () async {
      await configService.set('theme', 'dark');

      final file = File('data/global/config.json');
      expect(await file.exists(), true);
    });

    test('app overrides persist to disk', () async {
      await configService.set('fontSize', '18', appId: 'test_app');

      final file = File('data/test_app/config.json');
      expect(await file.exists(), true);
    });

    test('loadAppOverrides restores saved values', () async {
      await configService.set('fontSize', '20', appId: 'test_app');

      // Create a new instance to test loading
      final newService = ConfigService.instance;
      await newService.loadAppOverrides('test_app');

      expect(newService.get('fontSize', appId: 'test_app'), '20');
    });
  });
}
