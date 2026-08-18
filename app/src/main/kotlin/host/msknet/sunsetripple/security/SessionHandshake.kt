package host.msknet.sunsetripple.security

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameType
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

data class SignedHello(
    val publicKeyBase64: String,
    val nonceBase64: String,
    val signatureBase64: String,
)

object SessionHandshake {
    fun create(identity: DeviceIdentity, roomId: String, role: String): SignedHello {
        val nonce = ByteArray(32).also(SecureRandom()::nextBytes)
        val payload = transcript(roomId, role, identity.publicKeyBase64, nonce)
        return SignedHello(
            identity.publicKeyBase64,
            Base64.getEncoder().encodeToString(nonce),
            Base64.getEncoder().encodeToString(identity.sign(payload)),
        )
    }

    fun establish(
        localIdentity: DeviceIdentity,
        localHello: SignedHello,
        remoteHello: SignedHello,
        remoteRole: String,
        roomId: String,
    ): SessionCipher {
        val remoteNonce = Base64.getDecoder().decode(remoteHello.nonceBase64)
        require(remoteNonce.size == 32) { "invalid handshake nonce" }
        require(
            verifyDeviceSignature(
                remoteHello.publicKeyBase64,
                transcript(roomId, remoteRole, remoteHello.publicKeyBase64, remoteNonce),
                Base64.getDecoder().decode(remoteHello.signatureBase64),
            ),
        ) { "invalid device signature" }
        val localNonce = Base64.getDecoder().decode(localHello.nonceBase64)
        val orderedNonces = listOf(localNonce, remoteNonce).sortedWith { left, right -> compareBytes(left, right) }
        val context = MessageDigest.getInstance("SHA-256").digest(
            roomId.toByteArray() + orderedNonces[0] + orderedNonces[1],
        )
        return SessionCipher.establish(localIdentity.keyPair.private, remoteHello.publicKeyBase64, context)
    }

    private fun transcript(roomId: String, role: String, publicKey: String, nonce: ByteArray): ByteArray =
        listOf(PROTOCOL, roomId, role, publicKey, Base64.getEncoder().encodeToString(nonce))
            .joinToString("\u0000")
            .toByteArray()

    private fun compareBytes(left: ByteArray, right: ByteArray): Int {
        for (index in 0 until minOf(left.size, right.size)) {
            val compared = (left[index].toInt() and 0xff).compareTo(right[index].toInt() and 0xff)
            if (compared != 0) return compared
        }
        return left.size.compareTo(right.size)
    }

    private const val PROTOCOL = "sunset-ripple-alpha5"
}

class SecureFrameCodec(private val cipher: SessionCipher) {
    fun seal(frame: Frame): Frame {
        require(frame.type != FrameType.SEALED) { "frame is already sealed" }
        val packet = cipher.encrypt(frame.encode(), associatedData(frame.senderId, frame.seq))
        val payload = packet.nonce + packet.ciphertext
        require(payload.size <= Frame.MAX_PAYLOAD) { "sealed frame exceeds transport limit" }
        return Frame(FrameType.SEALED, frame.senderId, frame.seq, payload)
    }

    fun open(frame: Frame): Frame {
        require(frame.type == FrameType.SEALED) { "sealed frame required" }
        require(frame.payload.size >= NONCE_BYTES + TAG_BYTES) { "sealed frame is truncated" }
        val packet = EncryptedPacket(
            frame.payload.copyOfRange(0, NONCE_BYTES),
            frame.payload.copyOfRange(NONCE_BYTES, frame.payload.size),
        )
        val decoded = Frame.decode(cipher.decrypt(packet, associatedData(frame.senderId, frame.seq)))
        require(decoded.senderId == frame.senderId && decoded.seq == frame.seq) { "sealed frame header mismatch" }
        return decoded
    }

    private fun associatedData(senderId: Int, sequence: Int): ByteArray = ByteBuffer.allocate(5)
        .put(FrameType.SEALED.id.toByte())
        .put(senderId.toByte())
        .putShort(sequence.toShort())
        .put(PROTOCOL_VERSION)
        .array()

    companion object {
        const val MAX_PLAINTEXT_PAYLOAD = Frame.MAX_PAYLOAD - Frame.HEADER_SIZE - 12 - 16
        private const val NONCE_BYTES = 12
        private const val TAG_BYTES = 16
        private const val PROTOCOL_VERSION: Byte = 1
    }
}
