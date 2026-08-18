package host.msknet.sunsetripple.security

import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class DeviceIdentity(val keyPair: KeyPair) {
    val publicKeyBase64: String = Base64.getEncoder().encodeToString(keyPair.public.encoded)
    val fingerprint: String = DeviceFingerprint.full(keyPair.public.encoded)
    val shortCode: String = DeviceFingerprint.shortCode(keyPair.public.encoded)

    companion object {
        fun generate(): DeviceIdentity = DeviceIdentity(
            KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair(),
        )
    }
}

data class EncryptedPacket(val nonce: ByteArray, val ciphertext: ByteArray)

class SessionCipher private constructor(private val key: SecretKeySpec) {
    private val random = SecureRandom()
    private val seenNonces = linkedSetOf<String>()

    fun encrypt(plaintext: ByteArray, associatedData: ByteArray = byteArrayOf()): EncryptedPacket {
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        cipher.updateAAD(associatedData)
        return EncryptedPacket(nonce, cipher.doFinal(plaintext))
    }

    @Synchronized
    fun decrypt(packet: EncryptedPacket, associatedData: ByteArray = byteArrayOf()): ByteArray {
        val nonceId = Base64.getEncoder().encodeToString(packet.nonce)
        check(seenNonces.add(nonceId)) { "replayed encrypted frame" }
        if (seenNonces.size > MAX_SEEN_NONCES) seenNonces.remove(seenNonces.first())
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, packet.nonce))
            cipher.updateAAD(associatedData)
            cipher.doFinal(packet.ciphertext)
        } catch (error: Throwable) {
            seenNonces.remove(nonceId)
            throw error
        }
    }

    companion object {
        private const val NONCE_BYTES = 12
        private const val TAG_BITS = 128
        private const val MAX_SEEN_NONCES = 65_536

        fun fromKey(keyBytes: ByteArray): SessionCipher {
            require(keyBytes.size == 32) { "AES-256 key required" }
            return SessionCipher(SecretKeySpec(keyBytes.copyOf(), "AES"))
        }

        fun establish(
            localPrivateKey: PrivateKey,
            remotePublicKeyBase64: String,
            roomContext: ByteArray,
        ): SessionCipher {
            val remote = KeyFactory.getInstance("EC").generatePublic(
                X509EncodedKeySpec(Base64.getDecoder().decode(remotePublicKeyBase64)),
            )
            return establish(localPrivateKey, remote, roomContext)
        }

        fun establish(
            localPrivateKey: PrivateKey,
            remotePublicKey: PublicKey,
            roomContext: ByteArray,
        ): SessionCipher {
            val agreement = KeyAgreement.getInstance("ECDH")
            agreement.init(localPrivateKey)
            agreement.doPhase(remotePublicKey, true)
            val keyBytes = hkdf(agreement.generateSecret(), roomContext, "sunset-ripple-session".toByteArray(), 32)
            return SessionCipher(SecretKeySpec(keyBytes, "AES"))
        }

        private fun hkdf(secret: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(32) else salt, "HmacSHA256"))
            val pseudoRandomKey = mac.doFinal(secret)
            val output = ByteArray(length)
            var previous = byteArrayOf()
            var offset = 0
            var counter = 1
            while (offset < length) {
                mac.init(SecretKeySpec(pseudoRandomKey, "HmacSHA256"))
                mac.update(previous)
                mac.update(info)
                mac.update(counter.toByte())
                previous = mac.doFinal()
                val count = minOf(previous.size, length - offset)
                previous.copyInto(output, offset, 0, count)
                offset += count
                counter += 1
            }
            return output
        }
    }
}

fun DeviceIdentity.sign(payload: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run {
    initSign(keyPair.private)
    update(payload)
    sign()
}

fun verifyDeviceSignature(publicKeyBase64: String, payload: ByteArray, signature: ByteArray): Boolean = runCatching {
    val key = KeyFactory.getInstance("EC").generatePublic(
        X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)),
    )
    Signature.getInstance("SHA256withECDSA").run {
        initVerify(key)
        update(payload)
        verify(signature)
    }
}.getOrDefault(false)

object DeviceFingerprint {
    fun full(publicKey: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(publicKey)
        .joinToString(":") { "%02X".format(it) }

    fun shortCode(publicKey: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(publicKey)
        val value = ByteBuffer.wrap(digest.copyOfRange(0, 4)).int.toUInt().toLong() % 1_000_000
        return value.toString().padStart(6, '0').chunked(3).joinToString(" ")
    }
}
