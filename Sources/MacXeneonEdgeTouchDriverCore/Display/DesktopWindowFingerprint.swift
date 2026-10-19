import CryptoKit
import Foundation

/// The random local salt makes persisted window metadata unsuitable for sharing.
/// It is stored beside the private desktop snapshot, never in the app or repo.
final class DesktopWindowFingerprint {
    private let salt: Data?

    init(directory: URL = DriverConfiguration.defaultConfigURL().deletingLastPathComponent()) {
        let path = directory.appendingPathComponent("window-identity-salt")
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                let data = try Data(contentsOf: path)
                salt = data.count == 32 ? data : nil
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
                // Set protection at creation, before writing any bytes.
                guard FileManager.default.createFile(atPath: path.path, contents: data,
                    attributes: [.posixPermissions: 0o600]) else { salt = nil; return }
                salt = data
            }
        } catch { salt = nil }
    }

    func hash(_ value: String?, kind: String) -> String? {
        guard let salt, let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let input = Data((kind + "\0" + value.precomposedStringWithCanonicalMapping).utf8)
        return HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: salt))
            .map { String(format: "%02x", $0) }.joined()
    }
}
