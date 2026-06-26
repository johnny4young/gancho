#!/usr/bin/env swift
import CryptoKit
import Foundation

// Generates an Ed25519 keypair for Gancho's direct-download license tokens.
//
// Run ONCE to create your production keypair:
//   swift scripts/generate-license-keypair.swift ~/gancho-license-signing-key.txt
//
// - Prints the PUBLIC key (base64) to stdout. Paste it into
//   `LicenseVerifier.embedded` in
//   Packages/GanchoKit/Sources/GanchoKit/License.swift.
// - Writes the PRIVATE key (base64) to the path you pass (or stderr if you
//   omit it). Keep it SECRET, set it as the GANCHO_LICENSE_SIGNING_KEY
//   environment variable at release-build time, and NEVER commit it.
//
// A from-source / CI build with no injected private key cannot mint tokens and
// stays Free — that honor-model default is intentional.

let key = Curve25519.Signing.PrivateKey()
let publicB64 = key.publicKey.rawRepresentation.base64EncodedString()
let privateB64 = key.rawRepresentation.base64EncodedString()

print(publicB64)

func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
let note = "PRIVATE KEY — secret. Set as GANCHO_LICENSE_SIGNING_KEY at release; never commit.\n"
if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
    do {
        try privateB64.write(toFile: path, atomically: true, encoding: .utf8)
        err("Public key printed above.\n\(note)→ written to \(path)\n")
    } catch {
        err("Failed to write private key to \(path): \(error)\n")
        exit(1)
    }
} else {
    err(note)
    err(privateB64 + "\n")
}
