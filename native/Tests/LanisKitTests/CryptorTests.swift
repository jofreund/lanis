import Testing
import Foundation
@testable import LanisKit

@Suite struct CryptorTests {
    @Test func aesRoundTrip() throws {
        let c = SPHCryptor()
        let blob = try c.encrypt("Hällo Lanis ✓")
        #expect(Data(base64Encoded: blob)!.prefix(8) == Data("Salted__".utf8))
        #expect(c.decryptString(blob) == "Hällo Lanis ✓")
        #expect(SPHCryptor().decryptString(blob) == nil, "different key must not decrypt")
    }

    /// Vector produced with `openssl enc -aes-256-cbc -md md5 -pass pass:secret -a` ("hello").
    @Test func opensslCompatibility() throws {
        let c = SPHCryptor(key: Data("secret".utf8))
        #expect(c.decryptString("U2FsdGVkX1/BEKVgbsgkc273GD62ILOKXbQII5sE6w4=") == "hello")
    }

    @Test func bytesToKeyLength() {
        let (k, iv) = SPHCryptor.bytesToKeyAndIV(salt: Data(repeating: 1, count: 8), passphrase: Data("x".utf8))
        #expect(k.count == 32 && iv.count == 16)
    }

    @Test func encodedTags() throws {
        let c = SPHCryptor()
        let html = "<p>a</p><encoded>\(try c.encrypt("<b>secret</b>"))</encoded><p>z</p>"
        #expect(c.decryptEncodedTags(in: html) == "<p>a</p><b>secret</b><p>z</p>")
    }

    @Test func rsaHandshakeShape() throws {
        // Public key captured from ajax.php?f=rsaPublicKey (1024-bit SPKI).
        let pem = """
        -----BEGIN PUBLIC KEY-----
        MIGeMA0GCSqGSIb3DQEBAQUAA4GMADCBiAKBgGpTJwSxNDmELTK+qfZUowESiPD/
        rFaHQ7UyLEiLtleYGb6bvIFG+hAa25RY6ZP0a653QKfA5LFUs6IFQLU1JT9Uahtw
        HAAsb0oLWJukaa/6XGqRGTM3tKAWIQOxEqIxS8zBHdQZiZQZmuZlSrwdJwJLBoSr
        bp8iQWB1XMYlJigLAgMBAAE=
        -----END PUBLIC KEY-----
        """
        let key = try SPHCryptor.parsePublicKey(pem: pem)
        let enc = try SPHCryptor().encryptedKey(with: key)
        #expect(Data(base64Encoded: enc)?.count == 128)
    }
}
