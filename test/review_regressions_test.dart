import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/platform/platform_audio_channel.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';
import 'package:sunset_ripple/core/security/session_crypto.dart';
import 'package:sunset_ripple/core/security/session_handshake.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/core/transport/ble_l2cap_transport.dart';
import 'package:sunset_ripple/core/transport/lan_transport.dart';
import 'package:sunset_ripple/core/update/update_installer.dart';
import 'package:sunset_ripple/core/update/update_service.dart';

Future<void> waitUntil(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Uint8List token(int seed) => Uint8List.fromList(List.filled(16, seed));
Frame join(int seed) => Frame(
    type: FrameType.joinReq,
    senderId: 0,
    seq: 0,
    payload: JoinRequestPayload(nickname: 'member', sessionToken: token(seed))
        .encode());
Frame heartbeat(int id) => Frame(
    type: FrameType.heartbeat, senderId: id, seq: 5, payload: Uint8List(0));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('replacement JOIN binds new socket without removing member', () async {
    final host = LanTransport();
    final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'host');
    expect(await host.startHost(port: 0), isTrue);
    session.attachTransport(host);
    addTearDown(session.dispose);
    await session.createRoom(startAudio: false);
    final first = await Socket.connect(
        InternetAddress.loopbackIPv4, host.boundControlPort);
    first.listen((_) {});
    addTearDown(first.destroy);
    first.add(join(2).encode());
    await first.flush();
    await waitUntil(() => session.members.length == 2);
    for (var seed = 3; seed <= 6; seed++) {
      final peer = await Socket.connect(
          InternetAddress.loopbackIPv4, host.boundControlPort);
      peer.listen((_) {});
      addTearDown(peer.destroy);
      peer.add(join(seed).encode());
      await peer.flush();
    }
    await waitUntil(() => session.members.length == 6);
    final received = <Frame>[];
    final sub = host.incoming.listen(received.add);
    addTearDown(sub.cancel);
    final second = await Socket.connect(
        InternetAddress.loopbackIPv4, host.boundControlPort);
    second.listen((_) {});
    addTearDown(second.destroy);
    second.add(join(2).encode());
    await second.flush();
    await waitUntil(() => received.any((f) => f.type == FrameType.joinReq));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    second.add(heartbeat(2).encode());
    await second.flush();
    await waitUntil(() => received.any((f) => f.type == FrameType.heartbeat));
    expect(session.members.length, 6);
    expect(host.peerCount, 5);
    expect(received.where((f) => f.type == FrameType.leave), isEmpty);
  });

  test('reserved member cannot claim UDP endpoint before TCP identity binding',
      () async {
    final host = LanTransport();
    expect(await host.startHost(port: 0), isTrue);
    addTearDown(host.dispose);
    host.updateKnownMemberIds({2});
    final attacker =
        await RawDatagramSocket.bind(InternetAddress('127.0.0.2'), 0);
    final legit = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(attacker.close);
    addTearDown(legit.close);
    attacker.send(heartbeat(2).encode(), InternetAddress.loopbackIPv4,
        host.boundAudioPort);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(host.peerEndpoints, isEmpty);
    bool bound = false;
    final sub = host.incoming.listen((frame) {
      if (frame.type == FrameType.joinReq) {
        host.bindMemberForSessionToken(token(2), 2);
        bound = true;
      }
    });
    addTearDown(sub.cancel);
    final socket = await Socket.connect(
        InternetAddress.loopbackIPv4, host.boundControlPort);
    socket.listen((_) {});
    addTearDown(socket.destroy);
    socket.add(join(2).encode());
    await socket.flush();
    await waitUntil(() => bound);
    legit.send(heartbeat(2).encode(), InternetAddress.loopbackIPv4,
        host.boundAudioPort);
    await waitUntil(() => host.peerEndpoints[2] == '127.0.0.1');
    attacker.send(heartbeat(2).encode(), InternetAddress.loopbackIPv4,
        host.boundAudioPort);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(host.peerEndpoints[2], '127.0.0.1');
  });

  test('chat and PTT controls do not create audio sequence gaps', () async {
    final audio = MockAudioIo();
    final session = RoomSession(audioIo: audio, selfNickname: 'host');
    addTearDown(session.dispose);
    final sent = <Frame>[];
    session.onSendFrame = sent.add;
    await session.createRoom();
    audio.emitEncodedFrame(Uint8List.fromList([1]));
    await session.sendChat('hello');
    session.setPtt(true);
    audio.emitEncodedFrame(Uint8List.fromList([1]));
    final frames = sent.where((f) => f.type == FrameType.audio).toList();
    expect(frames.length, 2);
    expect((frames[1].seq - frames[0].seq) & 0xffff, 1);
    await session.handleIncomingFrame(Frame(
        type: FrameType.audio, senderId: 2, seq: 100, payload: Uint8List(0)));
    await session.handleIncomingFrame(Frame(
        type: FrameType.heartbeat,
        senderId: 2,
        seq: 500,
        payload: Uint8List(0)));
    await session.handleIncomingFrame(Frame(
        type: FrameType.audio, senderId: 2, seq: 101, payload: Uint8List(0)));
    expect(session.lostFrameCount, 0);
  });

  test('sealed roster is accepted, raw roster and replay remain rejected',
      () async {
    final session = RoomSession(audioIo: MockAudioIo(), selfNickname: 'member');
    addTearDown(session.dispose);
    await session.joinRoom(startAudio: false);
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    session.secureCodec = SecureFrameCodec(await SessionCipher.fromKey(key));
    final sender = SecureFrameCodec(await SessionCipher.fromKey(key));
    final roster = Frame(
        type: FrameType.roster,
        senderId: 1,
        seq: 1,
        payload: RosterPayload(hostId: 1, members: [
          RosterMember(memberId: 1, flags: 1, nickname: 'host'),
          RosterMember(memberId: 2, flags: 0, nickname: 'member'),
        ]).encode());
    await session.handleIncomingFrame(roster, recordStats: false);
    expect(session.state, RoomState.connecting);
    final sealed = await sender.seal(roster);
    await session.handleIncomingFrame(sealed);
    expect(session.state, RoomState.inRoom);
    expect(session.selfMemberId, 2);
    expect(session.receivedFrameCount, 1);
    await session.handleIncomingFrame(sealed);
    expect(session.receivedFrameCount, 1);
  });

  test('shared BLE remains usable after a real session is disposed', () async {
    const methods = MethodChannel('host.msknet.sunsetripple/ble_l2cap');
    const events = EventChannel('host.msknet.sunsetripple/ble_l2cap_data');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (_) async => true);
    messenger.setMockStreamHandler(
        events, MockStreamHandler.inline(onListen: (_, sink) {}));
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });
    final ble = BleL2capTransport();
    addTearDown(ble.dispose);
    final first = RoomSession(audioIo: MockAudioIo(), selfNickname: 'first');
    first.attachTransport(ble, ownsTransport: false);
    await first.createRoom(startAudio: false);
    var closed = false;
    final sub = ble.incoming.listen((_) {}, onDone: () {
      closed = true;
    });
    addTearDown(sub.cancel);
    await first.dispose();
    expect(closed, isFalse);
    expect(await ble.startHost(roomName: 'next'), isTrue);
    final next = RoomSession(audioIo: MockAudioIo(), selfNickname: 'next');
    next.attachTransport(ble, ownsTransport: false);
    await next.createRoom(startAudio: false);
    await next.dispose();
    expect(closed, isFalse);
  });

  test('native capture errors clear recording state and permit restart',
      () async {
    const methods = MethodChannel('host.msknet.sunsetripple/audio');
    const events = EventChannel('host.msknet.sunsetripple/audio_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int starts = 0;
    MockStreamHandlerEventSink? sink;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'startCapture') starts++;
      return true;
    });
    messenger.setMockStreamHandler(events,
        MockStreamHandler.inline(onListen: (_, value) {
      sink = value;
    }));
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });
    final audio = PlatformAudioChannel();
    final session = RoomSession(audioIo: audio, selfNickname: 'host');
    addTearDown(session.dispose);
    await session.createRoom();
    await waitUntil(() => sink != null);
    sink!.error(code: 'CAPTURE_STOPPED', message: 'read failed');
    await waitUntil(() => !audio.isRecording);
    await session.startAudio();
    expect(starts, 2);
    expect(audio.isRecording, isTrue);
  });

  for (final headers in [true, false]) {
    test('manifest deadline includes ${headers ? "headers" : "stalled body"}',
        () async {
      final client = _StalledClient(headers: headers);
      final installer = UpdateInstaller(
          clientFactory: () => client,
          manifestFetchTimeout: const Duration(milliseconds: 40));
      await expectLater(
          installer.fetchManifest(
              'https://github.com/Starlordzz/sunsetripple/releases/download/v1/update.json'),
          throwsA(isA<UpdateDownloadException>()));
      expect(client.closed, isTrue);
    });
    test(
        'update check deadline includes ${headers ? "headers" : "stalled body"}',
        () async {
      final client = _StalledClient(headers: headers);
      final service = UpdateService(
          clientFactory: () => client,
          requestTimeout: const Duration(milliseconds: 40));
      expect(await service.checkUpdate(), isA<UpdateFailed>());
      expect(client.closed, isTrue);
    });
  }
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StalledClient implements HttpClient {
  _StalledClient({required this.headers});
  final bool headers;
  bool closed = false;
  final _response = StreamController<List<int>>();
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(headers, _response);
  @override
  void close({bool force = false}) {
    closed = true;
    unawaited(_response.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.stalled, this.stream);
  final bool stalled;
  final StreamController<List<int>> stream;
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() => stalled
      ? Completer<HttpClientResponse>().future
      : Future.value(_Response(stream.stream));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.source);
  final Stream<List<int>> source;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => -1;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      source.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
