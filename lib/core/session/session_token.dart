import 'dart:typed_data';

/// Stable identity token used by the current wire protocol.
const int sessionTokenBytes = 16;

/// A valid token is fixed-size and must not be all zero.
bool isValidSessionToken(Uint8List token) =>
    token.length == sessionTokenBytes && token.any((byte) => byte != 0);
