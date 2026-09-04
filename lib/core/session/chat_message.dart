import 'package:flutter/foundation.dart';

/// In-memory chat message representation inside [RoomSession].
@immutable
class ChatMessage {
  final String messageId;
  final int senderId;
  final String senderCode;
  final String senderNickname;
  final String? previousNickname;
  final int seq;
  final String text;
  final DateTime timestamp;
  final bool isLocal;
  final bool isHost;
  final bool isRecalled;

  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderCode,
    required this.senderNickname,
    this.previousNickname,
    required this.seq,
    required this.text,
    required this.timestamp,
    required this.isLocal,
    this.isHost = false,
    this.isRecalled = false,
  });

  ChatMessage copyWith({
    String? messageId,
    int? senderId,
    String? senderCode,
    String? senderNickname,
    String? previousNickname,
    int? seq,
    String? text,
    DateTime? timestamp,
    bool? isLocal,
    bool? isHost,
    bool? isRecalled,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderCode: senderCode ?? this.senderCode,
      senderNickname: senderNickname ?? this.senderNickname,
      previousNickname: previousNickname ?? this.previousNickname,
      seq: seq ?? this.seq,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isLocal: isLocal ?? this.isLocal,
      isHost: isHost ?? this.isHost,
      isRecalled: isRecalled ?? this.isRecalled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;

  @override
  String toString() =>
      'ChatMessage(id: $messageId, sender: $senderId, code: $senderCode, nickname: $senderNickname, local: $isLocal)';
}

