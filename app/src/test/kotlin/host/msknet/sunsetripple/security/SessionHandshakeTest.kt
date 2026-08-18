package host.msknet.sunsetripple.security

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameType
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SessionHandshakeTest {
    @Test
    fun signedHandshakeDerivesMatchingFrameCiphers() {
        val host = DeviceIdentity.generate()
        val guest = DeviceIdentity.generate()
        val hostHello = SessionHandshake.create(host, "room-9", "host")
        val guestHello = SessionHandshake.create(guest, "room-9", "guest")
        val hostCodec = SecureFrameCodec(SessionHandshake.establish(host, hostHello, guestHello, "guest", "room-9"))
        val guestCodec = SecureFrameCodec(SessionHandshake.establish(guest, guestHello, hostHello, "host", "room-9"))
        val plain = Frame(FrameType.AUDIO, 4, 22, byteArrayOf(1, 2, 3))

        val opened = guestCodec.open(hostCodec.seal(plain))

        assertEquals(plain.type, opened.type)
        assertEquals(plain.senderId, opened.senderId)
        assertEquals(plain.seq, opened.seq)
        assertArrayEquals(plain.payload, opened.payload)
    }

    @Test
    fun tamperedIdentityAndReplayAreRejected() {
        val host = DeviceIdentity.generate()
        val guest = DeviceIdentity.generate()
        val hostHello = SessionHandshake.create(host, "room-9", "host")
        val guestHello = SessionHandshake.create(guest, "room-9", "guest")
        val tampered = guestHello.copy(publicKeyBase64 = DeviceIdentity.generate().publicKeyBase64)
        assertThrows(IllegalArgumentException::class.java) {
            SessionHandshake.establish(host, hostHello, tampered, "guest", "room-9")
        }
        val hostCodec = SecureFrameCodec(SessionHandshake.establish(host, hostHello, guestHello, "guest", "room-9"))
        val guestCodec = SecureFrameCodec(SessionHandshake.establish(guest, guestHello, hostHello, "host", "room-9"))
        val sealed = hostCodec.seal(Frame(FrameType.PING, 1, 2, byteArrayOf()))
        guestCodec.open(sealed)
        assertThrows(IllegalStateException::class.java) { guestCodec.open(sealed) }
    }
}
