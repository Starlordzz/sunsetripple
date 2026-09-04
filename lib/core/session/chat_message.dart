import 'package:flutter/foundation.dart';

/// In-memory chat message representation inside [RoomSession].
@immutable
class ChatMessage {
  final int senderId;
  final String senderNickname;
  final int seq;
  final String text;
  final DateTime timestamp;
  final bool isLocal;

  const ChatMessage({
    required this.senderId,
    required this.senderNickname,
    required this.seq,
    required this.text,
    required this.timestamp,
    required this.isLocal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          senderId == other.senderId &&
          seq == other.seq;

  @override
  int get hashCode => senderId.hashCode ^ seq.hashCode;

  @override
  String toString() =>
      'ChatMessage(sender: $senderId, nickname: $senderNickname, seq: $seq, local: $isLocal)';
}

