// Verifies a Sparkle EdDSA (ed25519) signature with a public key, as installed copies of
// the app do with SUPublicEDKey. Used by apply-appcast.sh and check-feed.sh.
//
// Usage: xcrun swift scripts/verify-ed-signature.swift <public key, base64> <signature, base64> <file>
// Exit code: 0 valid, 1 invalid, 2 bad arguments.

import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
    let keyData = Data(base64Encoded: args[1]),
    let signature = Data(base64Encoded: args[2]),
    let file = FileManager.default.contents(atPath: args[3]),
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write(Data("bad public key, signature or file\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: file) ? 0 : 1)
