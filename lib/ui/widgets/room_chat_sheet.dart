import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/session/chat_message.dart';
import '../../core/session/room_session.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet for in-memory room text chat.
class RoomChatSheet extends StatefulWidget {
  final RoomSession session;
  final bool isNight;

  const RoomChatSheet({
    super.key,
    required this.session,
    required this.isNight,
  });

  @override
  State<RoomChatSheet> createState() => _RoomChatSheetState();
}

class _RoomChatSheetState extends State<RoomChatSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<ChatMessage>? _chatSub;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // 监听新消息，若用户在底部附近则自动滚动
    _chatSub = widget.session.chatStream.listen((_) {
      if (mounted) {
        setState(() {});
        _maybeAutoScroll();
      }
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 90) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutQuad,
      );
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    final s = AppStrings.of(context);
    final byteCount = utf8.encode(text).length;
    if (byteCount > 480) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.chatMessageTooLong),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await widget.session.sendChat(text);
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.chatMessageTooLong),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final bg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final accentColor = isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral;

    final messages = widget.session.chatMessages;
    final activeMemberIds = widget.session.members.map((m) => m.memberId).toSet();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 拖拽指示条与标题栏
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 22, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.chatTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Semantics(
                      label: s.chatCloseSheet,
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: s.chatCloseSheet,
                        color: textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.8),

              // 2. 消息流展示区
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            s.chatEmptyHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: textSecondary.withValues(alpha: 0.75),
                              height: 1.5,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isLocal = msg.isLocal;
                          final isFormer = !isLocal && !activeMemberIds.contains(msg.senderId);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              crossAxisAlignment: isLocal
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!isLocal) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        msg.senderNickname,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                      if (isFormer) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${s.chatFormerMember})',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: textSecondary.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                ],
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.74,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isLocal
                                        ? (isNight
                                            ? AppTheme.nightSkyBlue
                                            : AppTheme.sunsetCoral)
                                        : (isNight
                                            ? const Color(0xFF1E2D44)
                                            : const Color(0xFFEFE7DE)),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isLocal ? 16 : 4),
                                      bottomRight: Radius.circular(isLocal ? 4 : 16),
                                    ),
                                    border: isLocal
                                        ? null
                                        : Border.all(
                                            color: textSecondary.withValues(alpha: 0.15),
                                            width: 0.6,
                                          ),
                                  ),
                                  child: Text(
                                    msg.text,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      color: isLocal ? Colors.white : textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // 3. 底部输入与发送栏
              const Divider(height: 1, thickness: 0.8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: s.chatInputPlaceholder,
                        textField: true,
                        child: TextField(
                          controller: _textController,
                          maxLines: 3,
                          minLines: 1,
                          style: TextStyle(fontSize: 15, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: s.chatInputPlaceholder,
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              color: textSecondary.withValues(alpha: 0.65),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: isNight
                                ? const Color(0xFF121B2B)
                                : const Color(0xFFF1ECE5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: s.chatSend,
                      button: true,
                      child: IconButton(
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.send_rounded, color: accentColor),
                        tooltip: s.chatSend,
                        onPressed: _handleSend,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

