import CryptoKit
import Foundation

/// Content hashing for copy verification and duplicate detection.
public enum MavicaHasher {

    public static func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
