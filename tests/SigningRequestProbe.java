import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.Signature;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.util.Arrays;
import java.util.Base64;

// Test-only verification with JDK standard libraries; never issues a Huawei certificate.
class SigningRequestProbe {
    record Node(int start, int value, int end, int tag) {}
    static Node read(byte[] bytes, int start) {
        int position = start;
        int tag = bytes[position++] & 255;
        int size = bytes[position++] & 255;
        if ((size & 128) != 0) {
            int count = size & 127;
            if (count == 0 || count > 4) throw new IllegalArgumentException("Unsupported DER length");
            size = 0;
            for (int i = 0; i < count; i++) size = (size << 8) | (bytes[position++] & 255);
        }
        if (size < 0 || position + size > bytes.length) throw new IllegalArgumentException("Invalid DER bounds");
        return new Node(start, position, position + size, tag);
    }
    static void require(boolean value, String message) {
        if (!value) throw new IllegalStateException(message);
    }
    public static void main(String[] args) throws Exception {
        char[] password = System.getenv("LW_SIGNING_TEST_PASSWORD").toCharArray();
        try {
            KeyStore store = KeyStore.getInstance("PKCS12");
            try (var input = Files.newInputStream(Path.of(args[0]))) { store.load(input, password); }
            require(store.getKey(args[2], password) != null, "Private key/alias missing");
            var certificate = (X509Certificate) store.getCertificate(args[2]);
            var key = (ECPublicKey) certificate.getPublicKey();
            require(certificate.getSubjectX500Principal().getName().contains(args[3]), "Unicode subject was corrupted");
            require(key.getParams().getOrder().bitLength() == 256, "Expected a 256-bit EC key");
            String pem = Files.readString(Path.of(args[1])).replaceAll("-----[^\\r\\n]+-----", "");
            byte[] csr = Base64.getMimeDecoder().decode(pem);
            Node outer = read(csr, 0);
            Node info = read(csr, outer.value());
            Node version = read(csr, info.value());
            Node subject = read(csr, version.end());
            require(Arrays.equals(certificate.getSubjectX500Principal().getEncoded(),
                Arrays.copyOfRange(csr, subject.start(), subject.end())), "CSR subject differs from the keystore");
            Node spki = read(csr, subject.end());
            require(Arrays.equals(key.getEncoded(), Arrays.copyOfRange(csr, spki.start(), spki.end())), "CSR does not match the P12 public key");
            Node algorithm = read(csr, info.end());
            Node oid = read(csr, algorithm.value());
            require(Arrays.equals(Arrays.copyOfRange(csr, oid.value(), oid.end()),
                new byte[]{42, (byte)134, 72, (byte)206, 61, 4, 3, 2}), "Expected SHA256withECDSA");
            Node bits = read(csr, algorithm.end());
            require(bits.tag() == 3 && csr[bits.value()] == 0, "Invalid signature BIT STRING");
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initVerify(key);
            signature.update(csr, info.start(), info.end() - info.start());
            require(signature.verify(Arrays.copyOfRange(csr, bits.value() + 1, bits.end())), "CSR proof-of-possession signature is invalid");
            System.out.println("P12 private key, EC-256, matching CSR public key and ECDSA signature verified.");
        } finally { Arrays.fill(password, '\0'); }
    }
}
