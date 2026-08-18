package host.msknet.sunsetripple.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SessionCryptoTest {
    @Test
    fun peersDeriveSameAuthenticatedCipher() {
        val alice = DeviceIdentity.generate()
        val bob = DeviceIdentity.generate()
        val context = "room-42".toByteArray()
        val aliceCipher = SessionCipher.establish(alice.keyPair.private, bob.keyPair.public, context)
        val bobCipher = SessionCipher.establish(bob.keyPair.private, alice.keyPair.public, context)
        val aad = "audio:7".toByteArray()

        val packet = aliceCipher.encrypt("hello".toByteArray(), aad)

        assertArrayEquals("hello".toByteArray(), bobCipher.decrypt(packet, aad))
        assertThrows(IllegalStateException::class.java) { bobCipher.decrypt(packet, aad) }
    }

    @Test
    fun fingerprintAndShortCodeAreStable() {
        val identity = DeviceIdentity.generate()

        assertEquals(identity.fingerprint, DeviceFingerprint.full(identity.keyPair.public.encoded))
        assertEquals(7, identity.shortCode.length)
    }
}
