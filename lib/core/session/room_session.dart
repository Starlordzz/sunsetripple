import 'dart:async';
import 'dart:typed_data';
import '../audio/audio_io.dart';
import '../audio/audio_mixer.dart';
import '../audio/jitter_buffer.dart';
import '../protocol/frame.dart';
import '../protocol/frame_type.dart';
import '../protocol/payloads/join_request.dart';
import '../protocol/payloads/leave.dart';
import '../protocol/payloads/ptt_state.dart';
import '../protocol/payloads/roster.dart';
import 'member.dart';

enum RoomState { idle, connecting, inRoom, reconnecting, disconnected }

/// Central Room Session State Machine & Intercom Orchestrator.
class RoomSession {
  final AudioIo audioIo;
  final String selfNickname;
  final Uint8List sessionToken;

  RoomState _state = RoomState.idle;
  bool _isHost = false;
  int _selfMemberId = 1;
  int _seq = 0;

  final Map<int, Member> _members = {};
  final Map<int, JitterBuffer> _jitterBuffers = {};
  Timer? _playbackLoopTimer;
  Timer? _heartbeatTimer;

  // UI Reactive Streams
  final _stateController = StreamController<RoomState>.broadcast();
  final _membersController = StreamController<List<Member>>.broadcast();
  final _waveController = StreamController<double>.broadcast();

  Stream<RoomState> get stateStream => _stateController.stream;
  Stream<List<Member>> get membersStream => _membersController.stream;
  Stream<double> get waveStream => _waveController.stream;

  RoomState get state => _state;
  bool get isHost => _isHost;
  bool get isMuted => audioIo.isMuted;
  bool isPttPressed = false;
  int get selfMemberId => _selfMemberId;
  List<Member> get members => _members.values.toList();

  RoomSession({
    required this.audioIo,
    required this.selfNickname,
    Uint8List? sessionToken,
  }) : sessionToken = sessionToken ?? Uint8List(16);

  /// Create a new room as Host.
  Future<void> createRoom() async {
    _isHost = true;
    _selfMemberId = 1;
    _members.clear();

    final selfMember = Member(
      memberId: _selfMemberId,
      nickname: selfNickname,
      sessionToken: sessionToken,
      isHost: true,
    );
    _members[_selfMemberId] = selfMember;

    _updateState(RoomState.inRoom);
    _notifyMembers();

    await _startAudioPipeline();
    _startHeartbeat();
  }

  /// Join an existing room as Client.
  Future<void> joinRoom() async {
    _isHost = false;
    _selfMemberId = 0; // Assigned by host on ROSTER
    _members.clear();

    _updateState(RoomState.connecting);

    // Send JOIN_REQ frame to host
    final joinPayload = JoinRequestPayload(
      nickname: selfNickname,
      sessionToken: sessionToken,
    );
    final joinFrame = Frame(
      type: FrameType.joinReq,
      senderId: 0,
      seq: _nextSeq(),
      payload: joinPayload.encode(),
    );
    sendFrame(joinFrame);

    await _startAudioPipeline();
    _startHeartbeat();
  }

  /// Handle incoming binary frame from network.
  void handleIncomingFrame(Frame frame) {
    switch (frame.type) {
      case FrameType.audio:
        _handleAudioFrame(frame);
        break;
      case FrameType.joinReq:
        _handleJoinReq(frame);
        break;
      case FrameType.roster:
        _handleRoster(frame);
        break;
      case FrameType.pttState:
        _handlePttState(frame);
        break;
      case FrameType.heartbeat:
        _handleHeartbeat(frame);
        break;
      case FrameType.leave:
        _handleLeave(frame);
        break;
      case FrameType.hostHandover:
      case FrameType.hostAnnounce:
        break;
    }
  }

  void _handleAudioFrame(Frame frame) {
    if (frame.senderId == _selfMemberId) return;

    final jb = _jitterBuffers.putIfAbsent(
      frame.senderId,
      () => JitterBuffer(),
    );
    jb.put(frame.seq, frame.payload);

    final sender = _members[frame.senderId];
    if (sender != null && !sender.isSpeaking) {
      sender.isSpeaking = true;
      _notifyMembers();
    }
  }

  void _handleJoinReq(Frame frame) {
    if (!_isHost) return;
    final payload = JoinRequestPayload.decode(frame.payload);
    if (payload == null) return;

    // Allocate next available memberId (2..6)
    int newId = 2;
    while (_members.containsKey(newId) && newId <= 6) {
      newId++;
    }
    if (newId > 6) return; // Room full

    _members[newId] = Member(
      memberId: newId,
      nickname: payload.nickname,
      sessionToken: payload.sessionToken,
    );

    _broadcastRoster();
    _notifyMembers();
  }

  void _handleRoster(Frame frame) {
    final payload = RosterPayload.decode(frame.payload);
    if (payload == null) return;

    _members.clear();
    for (final rm in payload.members) {
      _members[rm.memberId] = Member(
        memberId: rm.memberId,
        nickname: rm.nickname,
        isHost: rm.isHost,
        isMuted: rm.isMuted,
        isSpeaking: rm.isSpeaking,
      );
      if (rm.nickname == selfNickname && !isHost) {
        _selfMemberId = rm.memberId;
      }
    }

    if (_state != RoomState.inRoom) {
      _updateState(RoomState.inRoom);
    }
    _notifyMembers();
  }

  void _handlePttState(Frame frame) {
    final payload = PttStatePayload.decode(frame.payload);
    if (payload == null) return;

    final member = _members[frame.senderId];
    if (member != null) {
      member.isSpeaking = payload.isPressed;
      _notifyMembers();
    }
  }

  void _handleHeartbeat(Frame frame) {
    final member = _members[frame.senderId];
    if (member != null) {
      member.lastActiveAt = DateTime.now();
    }
  }

  void _handleLeave(Frame frame) {
    _members.remove(frame.senderId);
    _jitterBuffers.remove(frame.senderId);
    _notifyMembers();

    if (_isHost) {
      _broadcastRoster();
    }
  }

  void _broadcastRoster() {
    final rosterMembers = _members.values.map((m) {
      int flags = 0;
      if (m.isHost) flags |= 0x01;
      if (m.isMuted) flags |= 0x02;
      if (m.isSpeaking) flags |= 0x04;
      return RosterMember(memberId: m.memberId, flags: flags, nickname: m.nickname);
    }).toList();

    final payload = RosterPayload(hostId: _selfMemberId, members: rosterMembers);
    final frame = Frame(
      type: FrameType.roster,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: payload.encode(),
    );
    sendFrame(frame);
  }

  Future<void> _startAudioPipeline() async {
    // 1. Microphone capture
    await audioIo.startCapture((pcmSamples) {
      if (audioIo.isMuted || !isPttPressed) return;

      // Calculate audio amplitude for UI wave
      double sumSquares = 0;
      for (int i = 0; i < pcmSamples.length; i++) {
        final sample = pcmSamples[i];
        sumSquares += sample * sample;
      }
      final rms = sumSquares / pcmSamples.length;
      final normalized = (rms / 32767.0).clamp(0.0, 1.0);
      _waveController.add(normalized);

      // Send audio frame to peers
      final bytes = AudioMixer.int16ListToBytes(pcmSamples);
      final frame = Frame(
        type: FrameType.audio,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: bytes,
      );
      sendFrame(frame);
    });

    // 2. Playback loop (every 20ms)
    _playbackLoopTimer?.cancel();
    _playbackLoopTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final activeStreams = <Int16List>[];
      for (final entry in _jitterBuffers.entries) {
        final rawFrame = entry.value.pop();
        if (rawFrame != null) {
          final pcm = AudioMixer.bytesToInt16List(rawFrame);
          activeStreams.add(pcm);
        }
      }

      if (activeStreams.isNotEmpty) {
        final mixedPcm = AudioMixer.mixPcmStreams(activeStreams);
        audioIo.playPcm(mixedPcm);
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final frame = Frame(
        type: FrameType.heartbeat,
        senderId: _selfMemberId,
        seq: _nextSeq(),
        payload: Uint8List(0),
      );
      sendFrame(frame);
    });
  }

  void setPtt(bool pressed) {
    isPttPressed = pressed;
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isSpeaking = pressed;
      _notifyMembers();
    }

    final pttPayload = PttStatePayload(isPressed: pressed);
    final frame = Frame(
      type: FrameType.pttState,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: pttPayload.encode(),
    );
    sendFrame(frame);
  }

  void toggleMute() {
    audioIo.setMuted(!audioIo.isMuted);
    final self = _members[_selfMemberId];
    if (self != null) {
      self.isMuted = audioIo.isMuted;
      _notifyMembers();
    }
  }

  void setSpeakerphone(bool enabled) {
    audioIo.setSpeakerphone(enabled);
  }

  /// Hook for network transmission
  void Function(Frame frame)? onSendFrame;

  void sendFrame(Frame frame) {
    onSendFrame?.call(frame);
  }

  Future<void> leave() async {
    final leavePayload = LeavePayload();
    final frame = Frame(
      type: FrameType.leave,
      senderId: _selfMemberId,
      seq: _nextSeq(),
      payload: leavePayload.encode(),
    );
    sendFrame(frame);

    _playbackLoopTimer?.cancel();
    _playbackLoopTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await audioIo.stopCapture();
    await audioIo.stopPlayback();

    _members.clear();
    _jitterBuffers.clear();
    _updateState(RoomState.idle);
    _notifyMembers();
  }

  int _nextSeq() {
    _seq = (_seq + 1) & 0xFFFF;
    return _seq;
  }

  void _updateState(RoomState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void _notifyMembers() {
    _membersController.add(_members.values.toList());
  }

  void dispose() {
    leave();
    _stateController.close();
    _membersController.close();
    _waveController.close();
  }
}
