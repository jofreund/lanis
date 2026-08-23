import Foundation
import CryptoKit
import Security
import CommonCrypto

/// Lanis RSA handshake + OpenSSL-compatible AES-256-CBC for SPH payloads.
/// Port of `liblanis@0.1.2 lib/src/session/cryptor.dart`. Pure value type; the handshake
/// itself lives in `LanisSession` because it needs the cookie session.
public struct SPHCryptor: Sendable {
    public static let passphraseSize = 46

    /// Raw session passphrase (46 random bytes; SPH treats it as the "password"
    /// fed to EVP_BytesToKey, not as a direct AES key).
    public let key: Data

    public init(key: Data = SPHCryptor.randomKey()) {
        self.key = key
    }

    public static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: passphraseSize)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: RSA

    /// Parses the PEM public key SPH returns from `ajax.php?f=rsaPublicKey`.
    public static func parsePublicKey(pem: String) throws -> SecKey {
        let body = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw LanisError.parse("RSA PEM not base64") }
        // SPH sends SubjectPublicKeyInfo (BEGIN PUBLIC KEY). SecKey wants PKCS#1 RSAPublicKey,
        // so strip the SPKI header if present.
        let rsaDER = stripSPKIHeader(der)
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rsaDER as CFData, attrs as CFDictionary, &error) else {
            throw LanisError.parse("RSA key rejected: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        return key
    }

    /// Strips an X.509 SubjectPublicKeyInfo wrapper (rsaEncryption OID) if present.
    static func stripSPKIHeader(_ der: Data) -> Data {
        // rsaEncryption OID 1.2.840.113549.1.1.1 inside AlgorithmIdentifier
        let oid: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        let bytes = [UInt8](der)
        guard let range = bytes.firstRange(of: oid) else { return der }
        // After AlgorithmIdentifier comes BIT STRING: 0x03 <len> 0x00 <RSAPublicKey>
        var i = range.upperBound
        // skip NULL params (05 00)
        if i + 1 < bytes.count, bytes[i] == 0x05, bytes[i + 1] == 0x00 { i += 2 }
        guard i < bytes.count, bytes[i] == 0x03 else { return der }
        i += 1
        // length
        var len = Int(bytes[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(bytes[i]); i += 1 }
        }
        // unused-bits byte
        guard i < bytes.count, bytes[i] == 0x00 else { return der }
        i += 1
        return Data(bytes[i..<min(bytes.count, i + len - 1)])
    }

    /// RSA PKCS#1 v1.5 encryption of the session key, base64 for the handshake form.
    public func encryptedKey(with publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let out = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, key as CFData, &error) else {
            throw LanisError.unknown("RSA encrypt failed: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        return (out as Data).base64EncodedString()
    }

    /// True when the server's challenge decrypts to our key (handshake succeeded).
    public func verifyChallenge(base64: String) -> Bool {
        guard let blob = Data(base64Encoded: base64), let plain = try? decrypt(blob) else { return false }
        return plain == key
    }

    // MARK: OpenSSL EVP_BytesToKey (MD5, 1 iteration) → 32-byte key + 16-byte IV

    static func bytesToKeyAndIV(salt: Data, passphrase: Data) -> (key: Data, iv: Data) {
        var concatenated = Data()
        var current = Data()
        while concatenated.count < 48 {
            var pre = Data()
            if !current.isEmpty { pre.append(current) }
            pre.append(passphrase)
            pre.append(salt)
            current = Data(Insecure.MD5.hash(data: pre))
            concatenated.append(current)
        }
        return (concatenated.prefix(32), concatenated.subdata(in: 32..<48))
    }

    // MARK: AES-256-CBC, `Salted__` + salt + ciphertext (OpenSSL enc format)

    public func encrypt(_ plaintext: String) throws -> String {
        var salt = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &salt)
        let saltData = Data(salt)
        let (k, iv) = Self.bytesToKeyAndIV(salt: saltData, passphrase: key)
        let cipher = try Self.aesCBC(.encrypt, key: k, iv: iv, data: Data(plaintext.utf8))
        var out = Data("Salted__".utf8)
        out.append(saltData)
        out.append(cipher)
        return out.base64EncodedString()
    }

    public func decrypt(_ blob: Data) throws -> Data {
        guard blob.count >= 16, blob.prefix(8) == Data("Salted__".utf8) else {
            throw LanisError.parse("Missing Salted__ header")
        }
        let salt = blob.subdata(in: 8..<16)
        let (k, iv) = Self.bytesToKeyAndIV(salt: salt, passphrase: key)
        return try Self.aesCBC(.decrypt, key: k, iv: iv, data: blob.subdata(in: 16..<blob.count))
    }

    public func decryptString(_ base64: String) -> String? {
        guard let blob = Data(base64Encoded: base64), let plain = try? decrypt(blob) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// Replaces every `<encoded>…</encoded>` block in SPH HTML with its decrypted content.
    public func decryptEncodedTags(in html: String) -> String {
        guard html.contains("<encoded>") else { return html }
        let regex = try! NSRegularExpression(pattern: "<encoded>(.*?)</encoded>", options: [.dotMatchesLineSeparators])
        let ns = html as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            result += decryptString(ns.substring(with: m.range(at: 1))) ?? ""
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    enum Op { case encrypt, decrypt }

    static func aesCBC(_ op: Op, key: Data, iv: Data, data: Data) throws -> Data {
        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = key.withUnsafeBytes { k in
            iv.withUnsafeBytes { v in
                data.withUnsafeBytes { d in
                    CCCrypt(op == .encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, key.count, v.baseAddress,
                            d.baseAddress, data.count, &out, out.count, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw LanisError.parse("AES failed (\(status))") }
        return Data(out.prefix(moved))
    }
}
