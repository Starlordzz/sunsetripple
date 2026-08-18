import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

public final class SignUpdateManifest {
    private SignUpdateManifest() {}

    public static void main(String[] args) throws Exception {
        Map<String, String> options = parseOptions(args);
        int versionCode = positiveInt(required(options, "version-code"), "version-code");
        int minimumVersionCode = positiveInt(
                options.getOrDefault("minimum-version-code", "1"),
                "minimum-version-code");
        String versionName = required(options, "version-name");
        String channel = required(options, "channel");
        String packageName = required(options, "package-name");
        String apkUrl = required(options, "apk-url");
        String certificateSha256 = normalizedSha256(required(options, "certificate-sha256"));
        String summary = Files.readString(
                Path.of(required(options, "summary-file")),
                StandardCharsets.UTF_8).trim();
        Path apkPath = Path.of(required(options, "apk"));
        Path privateKeyPath = Path.of(required(options, "private-key"));
        Path outputPath = Path.of(required(options, "output"));
        String publicKeyBase64 = required(options, "public-key-base64");

        if (!channel.equals("stable") && !channel.equals("prerelease")) {
            throw new IllegalArgumentException("channel must be stable or prerelease");
        }
        if (!apkUrl.startsWith("https://")) {
            throw new IllegalArgumentException("apk-url must use HTTPS");
        }
        if (summary.isBlank()) {
            throw new IllegalArgumentException("summary-file must not be blank");
        }

        String apkSha256 = sha256(Files.readAllBytes(apkPath));
        String unsignedJson = manifestJson(
                versionCode,
                versionName,
                channel,
                minimumVersionCode,
                packageName,
                apkUrl,
                apkSha256,
                certificateSha256,
                summary,
                null);

        PrivateKey privateKey = KeyFactory.getInstance("EC").generatePrivate(
                new PKCS8EncodedKeySpec(Files.readAllBytes(privateKeyPath)));
        Signature signer = Signature.getInstance("SHA256withECDSA");
        signer.initSign(privateKey);
        signer.update(unsignedJson.getBytes(StandardCharsets.UTF_8));
        String signatureBase64 = Base64.getEncoder().encodeToString(signer.sign());

        PublicKey publicKey = KeyFactory.getInstance("EC").generatePublic(
                new X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)));
        Signature verifier = Signature.getInstance("SHA256withECDSA");
        verifier.initVerify(publicKey);
        verifier.update(unsignedJson.getBytes(StandardCharsets.UTF_8));
        if (!verifier.verify(Base64.getDecoder().decode(signatureBase64))) {
            throw new IllegalStateException("update private key does not match the configured public key");
        }

        String signedJson = manifestJson(
                versionCode,
                versionName,
                channel,
                minimumVersionCode,
                packageName,
                apkUrl,
                apkSha256,
                certificateSha256,
                summary,
                signatureBase64);
        Path parent = outputPath.toAbsolutePath().getParent();
        if (parent != null) Files.createDirectories(parent);
        Files.writeString(outputPath, signedJson + System.lineSeparator(), StandardCharsets.UTF_8);
        System.out.println("Signed update manifest: " + outputPath.toAbsolutePath());
        System.out.println("APK SHA-256: " + apkSha256);
    }

    private static String manifestJson(
            int versionCode,
            String versionName,
            String channel,
            int minimumVersionCode,
            String packageName,
            String apkUrl,
            String apkSha256,
            String certificateSha256,
            String summary,
            String signature) {
        return "{"
                + "\"versionCode\":" + versionCode
                + ",\"versionName\":" + quote(versionName)
                + ",\"channel\":" + quote(channel)
                + ",\"minimumVersionCode\":" + minimumVersionCode
                + ",\"packageName\":" + quote(packageName)
                + ",\"apkUrl\":" + quote(apkUrl)
                + ",\"apkSha256\":" + quote(apkSha256)
                + ",\"certificateSha256\":" + quote(certificateSha256)
                + ",\"summary\":" + quote(summary)
                + (signature == null ? "" : ",\"signature\":" + quote(signature))
                + "}";
    }

    private static String quote(String value) {
        StringBuilder result = new StringBuilder(value.length() + 2).append('"');
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            switch (character) {
                case '"' -> result.append("\\\"");
                case '\\' -> result.append("\\\\");
                case '\b' -> result.append("\\b");
                case '\f' -> result.append("\\f");
                case '\n' -> result.append("\\n");
                case '\r' -> result.append("\\r");
                case '\t' -> result.append("\\t");
                default -> {
                    if (character < 0x20) {
                        result.append(String.format("\\u%04x", (int) character));
                    } else {
                        result.append(character);
                    }
                }
            }
        }
        return result.append('"').toString();
    }

    private static Map<String, String> parseOptions(String[] args) {
        if (args.length % 2 != 0) {
            throw new IllegalArgumentException("arguments must be --name value pairs");
        }
        Map<String, String> options = new LinkedHashMap<>();
        for (int index = 0; index < args.length; index += 2) {
            String key = args[index];
            if (!key.startsWith("--") || key.length() == 2) {
                throw new IllegalArgumentException("invalid option: " + key);
            }
            options.put(key.substring(2), args[index + 1]);
        }
        return options;
    }

    private static String required(Map<String, String> options, String name) {
        String value = options.get(name);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("missing --" + name);
        }
        return value;
    }

    private static int positiveInt(String value, String name) {
        int parsed = Integer.parseInt(value);
        if (parsed <= 0) throw new IllegalArgumentException(name + " must be positive");
        return parsed;
    }

    private static String normalizedSha256(String value) {
        if (!value.matches("(?i)[0-9a-f]{64}")) {
            throw new IllegalArgumentException("certificate-sha256 must contain 64 hexadecimal characters");
        }
        return value.toLowerCase();
    }

    private static String sha256(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder result = new StringBuilder(digest.length * 2);
        for (byte value : digest) result.append(String.format("%02x", value & 0xff));
        return result.toString();
    }
}
