package host.msknet.sunsetripple.security

import android.content.Context
import java.io.File
import java.security.KeyFactory
import java.security.KeyPair
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

class DeviceIdentityStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "device-identity-v1")

    @Synchronized
    fun loadOrCreate(): DeviceIdentity {
        readIdentity()?.let { return it }
        val identity = DeviceIdentity.generate()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(
            Base64.getEncoder().encodeToString(identity.keyPair.public.encoded) + "\n" +
                Base64.getEncoder().encodeToString(identity.keyPair.private.encoded),
        )
        if (!temporary.renameTo(file)) {
            temporary.copyTo(file, overwrite = true)
            temporary.delete()
        }
        return identity
    }

    private fun readIdentity(): DeviceIdentity? = runCatching {
        val lines = file.readLines()
        require(lines.size == 2)
        val factory = KeyFactory.getInstance("EC")
        DeviceIdentity(
            KeyPair(
                factory.generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(lines[0]))),
                factory.generatePrivate(PKCS8EncodedKeySpec(Base64.getDecoder().decode(lines[1]))),
            ),
        )
    }.getOrNull()
}
