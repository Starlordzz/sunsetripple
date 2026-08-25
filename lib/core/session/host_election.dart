/// 旧的按 [Member.joinedAt] 选举已删除。
///
/// 设备时钟回拨会让「谁更资深」翻转，选举结果必须在所有成员上算出同一个答案，
/// 所以改成房主分配的单调 [joinOrder]。实现见 [host_transfer.dart]。
library;

export 'host_transfer.dart' show HostElection, TransferCandidate;
