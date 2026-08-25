import 'dart:convert';
import 'dart:typed_data';

import '../protocol/frame.dart';

/// 房主转移的候选成员快照。
class TransferCandidate {
  final int memberId;

  /// 入房顺序。单调递增的整数，由房主分配。
  ///
  /// 不能用时间戳：设备时钟回拨会让「谁更资深」这件事发生翻转，
  /// 而选举结果必须在所有成员上算出同一个答案。
  final int joinOrder;

  final String nickname;

  /// 重连用的端点。WiFi 房是对端 IP，蓝牙房是 MAC 地址。
  final String endpoint;

  final bool connected;

  const TransferCandidate({
    required this.memberId,
    required this.joinOrder,
    required this.nickname,
    required this.endpoint,
    this.connected = true,
  });
}

/// 交接计划里的一个成员。
class HostTransferMember {
  final int memberId;
  final int joinOrder;
  final String nickname;
  final String endpoint;

  const HostTransferMember({
    required this.memberId,
    required this.joinOrder,
    required this.nickname,
    required this.endpoint,
  });

  @override
  String toString() =>
      'HostTransferMember($memberId, order=$joinOrder, $nickname @ $endpoint)';
}

/// 一份完整的房主交接计划：谁接任，以及接任后房里还有谁、怎么找到他们。
///
/// 校验规则逐条对齐已发布的 Kotlin 版（`transport/HostTransfer.kt`）。
/// 这些断言不是防御性冗余——成员号或端点重复会让重连时两个人抢同一个身份。
class HostTransferPlan {
  static const int maxMembers = 6;

  final int successorId;
  final List<HostTransferMember> members;

  HostTransferPlan({
    required this.successorId,
    required this.members,
  }) {
    if (successorId < 1 || successorId > 255) {
      throw ArgumentError('继任成员 ID 越界: $successorId');
    }
    if (members.isEmpty || members.length > maxMembers) {
      throw ArgumentError('交接成员数越界: ${members.length}');
    }
    if (members.map((m) => m.memberId).toSet().length != members.length) {
      throw ArgumentError('交接成员 ID 重复');
    }
    if (members.map((m) => m.endpoint.toLowerCase()).toSet().length !=
        members.length) {
      throw ArgumentError('交接成员端点重复');
    }
    if (members.map((m) => m.joinOrder).toSet().length != members.length) {
      throw ArgumentError('交接 joinOrder 重复');
    }
    if (!members.any((m) => m.memberId == successorId)) {
      throw ArgumentError('交接成员表不含继任者 $successorId');
    }
    for (final m in members) {
      if (m.memberId < 1 || m.memberId > 255) {
        throw ArgumentError('交接成员 ID 越界: ${m.memberId}');
      }
      if (m.joinOrder < 0) {
        throw ArgumentError('joinOrder 不能为负数');
      }
      if (m.endpoint.trim().isEmpty) {
        throw ArgumentError('交接端点不能为空');
      }
    }
  }

  HostTransferMember get successor =>
      members.firstWhere((m) => m.memberId == successorId);
}

/// 继任者选举。
///
/// 规则与旧版一致：在「已连接且端点非空」的候选里，按 joinOrder 升序、
/// 同序再按 memberId 升序，取第一个。所有成员用同一份快照算，结果必须相同。
class HostElection {
  /// 选出继任者；没有合格候选时返回 null。
  static TransferCandidate? select(List<TransferCandidate> candidates) {
    final active = _active(candidates);
    return active.isEmpty ? null : active.first;
  }

  /// 生成完整交接计划；没有合格候选时返回 null。
  static HostTransferPlan? plan(List<TransferCandidate> candidates) {
    final active = _active(candidates);
    if (active.isEmpty) return null;

    return HostTransferPlan(
      successorId: active.first.memberId,
      members: active
          .map((c) => HostTransferMember(
                memberId: c.memberId,
                joinOrder: c.joinOrder,
                nickname: c.nickname,
                endpoint: c.endpoint,
              ))
          .toList(),
    );
  }

  static List<TransferCandidate> _active(List<TransferCandidate> candidates) {
    final active = candidates
        .where((c) => c.connected && c.endpoint.trim().isNotEmpty)
        .toList();
    active.sort((a, b) {
      final byOrder = a.joinOrder.compareTo(b.joinOrder);
      return byOrder != 0 ? byOrder : a.memberId.compareTo(b.memberId);
    });
    return active;
  }
}

/// 重编号之后的成员。
class SeededTransferMember {
  /// 交接前的成员号，用来把旧名单上的人对应过来。
  final int previousId;

  /// 交接后的成员号。继任者为 0（随后作为房主取 1）。
  final int newId;

  final int joinOrder;
  final String nickname;
  final String endpoint;

  const SeededTransferMember({
    required this.previousId,
    required this.newId,
    required this.joinOrder,
    required this.nickname,
    required this.endpoint,
  });
}

/// 把交接计划展开成新房主要用的成员表。
///
/// 交接后所有人的成员号都会变，这一点很容易被忽略：继任者排到最前，
/// 其余按 joinOrder 顺延。传输层必须跟着更新自己的成员号，
/// 否则房主会把语音转发到错误的端点。
class HostTransferSeed {
  final List<SeededTransferMember> members;

  /// 下一个新成员该拿的 joinOrder。
  final int nextJoinOrder;

  const HostTransferSeed({
    required this.members,
    required this.nextJoinOrder,
  });

  SeededTransferMember get host => members.first;

  /// 按端点索引除房主外的成员，新房主用它认领重连上来的人。
  Map<String, SeededTransferMember> expectedByEndpoint() => {
        for (final m in members.skip(1)) m.endpoint: m,
      };

  static HostTransferSeed from(HostTransferPlan plan) {
    final ordered = [...plan.members]..sort((a, b) {
        final byOrder = a.joinOrder.compareTo(b.joinOrder);
        return byOrder != 0 ? byOrder : a.memberId.compareTo(b.memberId);
      });

    final successor = ordered.firstWhere((m) => m.memberId == plan.successorId);
    final rest = ordered.where((m) => m.memberId != plan.successorId).toList();

    final remapped = <SeededTransferMember>[
      _seed(successor, 0),
      for (int i = 0; i < rest.length; i++) _seed(rest[i], i + 1),
    ];

    final maxOrder =
        ordered.map((m) => m.joinOrder).reduce((a, b) => a > b ? a : b);

    return HostTransferSeed(
      members: remapped,
      nextJoinOrder: maxOrder + 1,
    );
  }

  static SeededTransferMember _seed(HostTransferMember m, int newId) =>
      SeededTransferMember(
        previousId: m.memberId,
        newId: newId,
        joinOrder: m.joinOrder,
        nickname: m.nickname,
        endpoint: m.endpoint,
      );
}

/// 交接计划的二进制编解码。
///
/// 格式与已发布的 Kotlin 版 `HostTransferCodec` 逐字节一致：
///
/// ```
/// version(1) | successorId(1) | count(1)
/// 重复 count 次:
///   memberId(1) | joinOrder(8, 大端有符号) |
///   nickLen(1) | nickname(UTF-8) | epLen(1) | endpoint(ASCII)
/// ```
///
/// 总长不得超过 [Frame.maxPayloadSize]（512）。
class HostTransferCodec {
  static const int version = 1;

  /// 昵称最长 64 字节，与 roster 的截断规则一致。
  static const int maxNicknameBytes = 64;

  static Uint8List encode(HostTransferPlan plan) {
    final out = BytesBuilder();
    out.addByte(version);
    out.addByte(plan.successorId);
    out.addByte(plan.members.length);

    for (final m in plan.members) {
      final nickname = _truncateUtf8(m.nickname, maxNicknameBytes);
      final endpoint = _asciiBytes(m.endpoint);

      out.addByte(m.memberId);
      out.add(_int64BigEndian(m.joinOrder));
      out.addByte(nickname.length);
      out.add(nickname);
      out.addByte(endpoint.length);
      out.add(endpoint);
    }

    final bytes = out.toBytes();
    if (bytes.length > Frame.maxPayloadSize) {
      throw ArgumentError('交接载荷超上限: ${bytes.length}');
    }
    return bytes;
  }

  /// 解码失败一律抛异常：交接载荷坏掉时宁可放弃这次交接，
  /// 也不能拿半份名单去重建房间。
  static HostTransferPlan decode(Uint8List payload) {
    if (payload.length > Frame.maxPayloadSize) {
      throw ArgumentError('交接载荷超上限: ${payload.length}');
    }
    final reader = _ByteReader(payload);

    if (reader.remaining < 3) throw ArgumentError('交接载荷字段不完整');
    if (reader.readUint8() != version) throw ArgumentError('不支持的交接版本');

    final successorId = reader.readUint8();
    final count = reader.readUint8();
    if (count < 1 || count > HostTransferPlan.maxMembers) {
      throw ArgumentError('交接成员数越界: $count');
    }

    final members = <HostTransferMember>[];
    for (int i = 0; i < count; i++) {
      if (reader.remaining < 11) throw ArgumentError('交接成员 $i 字段不完整');

      final memberId = reader.readUint8();
      final joinOrder = reader.readInt64();
      final nickname = utf8.decode(
        reader.readBytes(reader.readUint8(), '交接成员 $i 昵称'),
      );

      if (reader.remaining < 1) throw ArgumentError('交接成员 $i 缺少端点长度');
      final endpointLength = reader.readUint8();
      if (endpointLength == 0) throw ArgumentError('交接成员 $i 端点为空');

      final endpointBytes = reader.readBytes(endpointLength, '交接成员 $i 端点');
      if (endpointBytes.any((b) => b > 0x7F)) {
        throw ArgumentError('交接成员 $i 端点不是 ASCII');
      }

      members.add(HostTransferMember(
        memberId: memberId,
        joinOrder: joinOrder,
        nickname: nickname,
        endpoint: String.fromCharCodes(endpointBytes),
      ));
    }

    if (reader.remaining != 0) {
      throw ArgumentError('交接载荷尾部多余 ${reader.remaining} 字节');
    }

    return HostTransferPlan(successorId: successorId, members: members);
  }

  static Uint8List _int64BigEndian(int value) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setInt64(0, value, Endian.big);
    return bytes;
  }

  /// 按 UTF-8 字节数截断且不切断多字节字符（中文昵称会踩到）。
  static Uint8List _truncateUtf8(String text, int maxBytes) {
    var candidate = text;
    while (candidate.isNotEmpty) {
      final bytes = utf8.encode(candidate);
      if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
      candidate = candidate.substring(0, candidate.length - 1);
    }
    return Uint8List(0);
  }

  static Uint8List _asciiBytes(String endpoint) {
    if (endpoint.trim().isEmpty) throw ArgumentError('交接端点不能为空');
    if (endpoint.codeUnits.any((c) => c < 1 || c > 0x7F)) {
      throw ArgumentError('交接端点必须为 ASCII: $endpoint');
    }
    final bytes = Uint8List.fromList(endpoint.codeUnits);
    if (bytes.length > 255) throw ArgumentError('交接端点过长: ${bytes.length}');
    return bytes;
  }
}

class _ByteReader {
  final Uint8List _data;
  int _offset = 0;

  _ByteReader(this._data);

  int get remaining => _data.length - _offset;

  int readUint8() => _data[_offset++];

  int readInt64() {
    final value =
        ByteData.sublistView(_data, _offset, _offset + 8).getInt64(0, Endian.big);
    _offset += 8;
    return value;
  }

  Uint8List readBytes(int length, String field) {
    if (remaining < length) throw ArgumentError('$field 长度越界: $length');
    final slice = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(slice);
  }
}
