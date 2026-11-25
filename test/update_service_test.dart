import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/update/update_service.dart';
import 'package:sunset_ripple/core/version.dart';

void main() {
  group('UpdateService SemVer Comparison Tests', () {
    test('Older pre-release (alpha.9) is NOT newer than current (alpha.10)',
        () {
      expect(UpdateService.isNewer('0.1.0-alpha.9', '0.1.0-alpha.10'), isFalse);
      expect(
          UpdateService.isNewer('v0.1.0-alpha.9', '0.1.0-alpha.10'), isFalse);
    });

    test('Identical version is NOT newer', () {
      expect(
          UpdateService.isNewer('0.1.0-alpha.10', '0.1.0-alpha.10'), isFalse);
      expect(
          UpdateService.isNewer('v0.1.0-alpha.10', '0.1.0-alpha.10'), isFalse);
    });

    test(
        'Newer pre-release or channel (alpha.11, beta.1, rc.1) IS newer than alpha.10',
        () {
      expect(UpdateService.isNewer('0.1.0-alpha.11', '0.1.0-alpha.10'), isTrue);
      expect(
          UpdateService.isNewer('v0.1.0-alpha.11', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.1.0-beta.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.1.0-rc.1', '0.1.0-alpha.10'), isTrue);
    });

    test('Formal release 0.1.0 is newer than pre-release 0.1.0-alpha.10', () {
      expect(UpdateService.isNewer('0.1.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('v0.1.0', '0.1.0-alpha.10'), isTrue);
    });

    test('Major and minor version bumps are newer', () {
      expect(UpdateService.isNewer('0.2.0-alpha.1', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '0.1.0-alpha.10'), isTrue);
      expect(UpdateService.isNewer('0.0.9', '0.1.0-alpha.10'), isFalse);
    });

    test('Build metadata (+...) is handled correctly', () {
      // Build metadata should be ignored in version precedence comparison
      expect(UpdateService.isNewer('0.1.0-alpha.11+13', '0.1.0-alpha.11+12'),
          isFalse);
      expect(UpdateService.isNewer('0.1.0-alpha.11+12', '0.1.0-alpha.11'),
          isFalse);
      expect(UpdateService.isNewer('0.1.0-alpha.12+1', '0.1.0-alpha.11+12'),
          isTrue);
    });

    test('Current version constant matches pubspec.yaml', () {
      expect(UpdateService.currentVersion, AppVersion.name);
    });
  });

  group('UpdateService Release 选择', () {
    Map<String, dynamic> release(
      String tag, {
      bool prerelease = true,
      bool draft = false,
      String createdAt = '2026-09-29T00:00:00Z',
      List<Map<String, dynamic>> assets = const [],
    }) =>
        <String, dynamic>{
          'tag_name': tag,
          'prerelease': prerelease,
          'draft': draft,
          'created_at': createdAt,
          'assets': assets,
        };

    test('预发布渠道取最高 SemVer，滚动通道那种固定 tag 不算版本', () {
      final selected = UpdateService.selectRelease(
        [
          release('v0.1.0-alpha.13', createdAt: '2026-09-17T00:00:00Z'),
          release('updates-prerelease', createdAt: '2026-09-30T00:00:00Z'),
          release('v0.1.0-alpha.14', createdAt: '2026-09-29T00:00:00Z'),
          release('v0.1.0-alpha.8', createdAt: '2026-08-25T00:00:00Z'),
        ],
        includePrerelease: true,
      );
      expect(selected?['tag_name'], 'v0.1.0-alpha.14');
    });

    test('正式渠道不会把 alpha 当更新', () {
      final selected = UpdateService.selectRelease(
        [
          release('v0.1.0-alpha.14'),
          release('v0.1.0-beta.1'),
        ],
        includePrerelease: false,
      );
      expect(selected, isNull);
    });

    test('正式渠道只看正式版，且正式版优先于更新的预发布', () {
      final selected = UpdateService.selectRelease(
        [
          release('v0.1.0-alpha.14'),
          release('v0.1.0',
              prerelease: false, createdAt: '2026-09-01T00:00:00Z'),
        ],
        includePrerelease: false,
      );
      expect(selected?['tag_name'], 'v0.1.0');
    });

    test('draft 即使版本最高也不选', () {
      final selected = UpdateService.selectRelease(
        [
          release('v0.1.0-alpha.14'),
          release('v0.1.0-alpha.99', draft: true),
        ],
        includePrerelease: true,
      );
      expect(selected?['tag_name'], 'v0.1.0-alpha.14');
    });

    test('空列表或全是非版本 tag 时返回 null', () {
      expect(
        UpdateService.selectRelease(const [], includePrerelease: true),
        isNull,
      );
      expect(
        UpdateService.selectRelease(
          [release('updates-stable'), release('nightly')],
          includePrerelease: true,
        ),
        isNull,
      );
    });

    test('SemVer 相同则取后发布的', () {
      final selected = UpdateService.selectRelease(
        [
          release('v0.1.0-alpha.14', createdAt: '2026-09-29T00:00:00Z'),
          release('v0.1.0-alpha.14', createdAt: '2026-09-30T00:00:00Z'),
        ],
        includePrerelease: true,
      );
      expect(selected?['created_at'], '2026-09-30T00:00:00Z');
    });

    test('Release 列表非空但无匹配 SemVer 版本时返回 UpdateUpToDate 而非失败', () async {
      final payload = jsonEncode([
        release('updates-prerelease'),
        release('v9.9.9', draft: true),
      ]);
      final service = UpdateService(
        clientFactory: () => _MockReleasesClient(payload),
      );
      final state = await service.checkUpdate();
      expect(state, isA<UpdateUpToDate>());
    });
  });
}

class _MockHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockReleasesClient implements HttpClient {
  _MockReleasesClient(this.body);
  final String body;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockRequest(body);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockRequest implements HttpClientRequest {
  _MockRequest(this.body);
  final String body;
  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockResponse(body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockResponse extends Stream<List<int>> implements HttpClientResponse {
  _MockResponse(this.body);
  final String body;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(utf8.encode(body)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
