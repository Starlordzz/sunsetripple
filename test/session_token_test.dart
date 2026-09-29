import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/session/session_token.dart';

Uint8List token(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('会话令牌生成与校验', () {
    test('生成的令牌是 16 字节、通过校验、且两次不重复', () {
      final first = generateSessionToken();
      final second = generateSessionToken();

      expect(first.length, sessionTokenBytes);
      expect(isValidSessionToken(first), isTrue);
      expect(first, isNot(second));
    });

    test('全零、长度不对的令牌都不合法', () {
      expect(isValidSessionToken(token(List<int>.filled(16, 0))), isFalse);
      expect(isValidSessionToken(token(List<int>.filled(15, 7))), isFalse);
      expect(isValidSessionToken(Uint8List(0)), isFalse);
    });

    test('逐字节比较：相同为真，长度或内容不同为假', () {
      final base = token(List<int>.generate(16, (i) => i));

      expect(sessionTokensEqual(base, token(List<int>.generate(16, (i) => i))),
          isTrue);
      expect(sessionTokensEqual(base, token(List<int>.generate(15, (i) => i))),
          isFalse);
    });

    test('只差一个字节也判为不同（不能在鉴权路径上短路）', () {
      final base = token(List<int>.filled(16, 0x42));
      final mutated = token(List<int>.filled(16, 0x42));
      mutated[15] = 0x43;

      expect(sessionTokensEqual(base, mutated), isFalse);
    });
  });
}
