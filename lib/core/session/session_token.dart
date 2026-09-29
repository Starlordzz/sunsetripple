import 'dart:math';
import 'dart:typed_data';

/// Stable identity token used by the current wire protocol.
const int sessionTokenBytes = 16;

/// A valid token is fixed-size and must not be all zero.
bool isValidSessionToken(Uint8List token) =>
    token.length == sessionTokenBytes && token.any((byte) => byte != 0);

/// 生成一枚新的会话令牌。
///
/// 用 [Random.secure]：令牌是房主判定「重连的老成员」还是「同昵称的新人」的
/// 唯一依据，可预测的伪随机数会让攻击者可以顶掉在册成员的身份。
Uint8List generateSessionToken() {
  final token = Uint8List(sessionTokenBytes);
  final rng = Random.secure();
  for (int i = 0; i < token.length; i++) {
    token[i] = rng.nextInt(256);
  }
  return token;
}

/// 比较两枚令牌是否逐字节相同。
///
/// 定长比较，不用 `listEquals`：调用点在 JOIN 鉴权路径上，语义必须只有
/// 「完全相同 / 不同」两种，不能因为长度差异就短路出错。
bool sessionTokensEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
