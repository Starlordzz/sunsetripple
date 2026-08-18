import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;
import java.util.List;

public final class GenerateUpdateSigningKey {
    private GenerateUpdateSigningKey() {}

    public static void main(String[] args) throws Exception {
        Path outputDirectory = args.length == 0
                ? Path.of(".update-signing")
                : Path.of(args[0]);
        Files.createDirectories(outputDirectory);

        List<Path> outputFiles = List.of(
                outputDirectory.resolve("update-private-key.pem"),
                outputDirectory.resolve("update-private-key.pk8"),
                outputDirectory.resolve("update-public-key.pem"),
                outputDirectory.resolve("update-public-key.der"),
                outputDirectory.resolve("gradle-public-key.properties"));
        List<Path> existingFiles = outputFiles.stream().filter(Files::exists).toList();
        if (!existingFiles.isEmpty()) {
            throw new IllegalStateException(
                    "Refusing to overwrite existing update signing key files: " + existingFiles);
        }

        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        KeyPair keyPair = generator.generateKeyPair();

        byte[] privateKey = keyPair.getPrivate().getEncoded();
        byte[] publicKey = keyPair.getPublic().getEncoded();
        String publicKeyBase64 = Base64.getEncoder().encodeToString(publicKey);

        writePem(
                outputDirectory.resolve("update-private-key.pem"),
                "PRIVATE KEY",
                privateKey);
        writePem(
                outputDirectory.resolve("update-public-key.pem"),
                "PUBLIC KEY",
                publicKey);
        Files.write(outputDirectory.resolve("update-private-key.pk8"), privateKey);
        Files.write(outputDirectory.resolve("update-public-key.der"), publicKey);
        Files.writeString(
                outputDirectory.resolve("gradle-public-key.properties"),
                "sunsetRipple.updatePublicKey=" + publicKeyBase64 + System.lineSeparator(),
                StandardCharsets.US_ASCII);

        String fingerprint = toHex(MessageDigest.getInstance("SHA-256").digest(publicKey));
        System.out.println("Update signing key generated in: " + outputDirectory.toAbsolutePath());
        System.out.println("Public key SHA-256: " + fingerprint);
        System.out.println("Gradle property:");
        System.out.println("sunsetRipple.updatePublicKey=" + publicKeyBase64);
        System.out.println("Keep update-private-key.pem and update-private-key.pk8 secret.");
    }

    private static void writePem(Path path, String label, byte[] encoded) throws Exception {
        String body = Base64.getMimeEncoder(64, System.lineSeparator().getBytes(StandardCharsets.US_ASCII))
                .encodeToString(encoded);
        String pem = "-----BEGIN " + label + "-----" + System.lineSeparator()
                + body + System.lineSeparator()
                + "-----END " + label + "-----" + System.lineSeparator();
        Files.writeString(path, pem, StandardCharsets.US_ASCII);
    }

    private static String toHex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            result.append(String.format("%02x", value & 0xff));
        }
        return result.toString();
    }
}
