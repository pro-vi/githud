import Foundation
import Security

/// Reads the GitHub **classic** Personal Access Token from the login Keychain via
/// Security.framework — never from disk, never logged (RUBRIC #9, credential
/// safety). The token authenticates the Notifications API; it MUST be a classic
/// PAT (pressure `notifications-classic-pat`: the API 403s/empties on fine-grained
/// or App tokens).
public enum KeychainPAT {
    public static let service = "githud.github.pat"
    public static let account = "github"

    public enum ReadError: Error, Equatable {
        case notFound
        case unexpectedData
        case status(OSStatus)
    }

    /// A Keychain WRITE outcome (store/delete). Carries only the `OSStatus` code — never the
    /// token value (never-log discipline): the secret never reaches an error, log, or display.
    public enum WriteError: Error, Equatable {
        case status(OSStatus)
    }

    /// Read the token. The returned string is sensitive — never print or log it.
    public static func read(service: String = service, account: String = account) -> Result<String, ReadError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                return .failure(.unexpectedData)
            }
            return .success(token.trimmingCharacters(in: .whitespacesAndNewlines))
        case errSecItemNotFound:
            return .failure(.notFound)
        default:
            return .failure(.status(status))
        }
    }

    /// Write the token to the Keychain (add-or-update). A RAW primitive: it does NOT gate on
    /// shape — the classic-PAT WALL (`notifications-classic-pat`) is enforced by the caller's
    /// intake path (`looksLikeClassicPAT`) BEFORE any call here, so this never sees a rejected
    /// shape. Add-vs-update: try `SecItemUpdate` on the {service, account} identity first;
    /// `errSecItemNotFound` means the item is absent → `SecItemAdd`. Accessibility is
    /// `kSecAttrAccessibleAfterFirstUnlock` — readable by the background agent after the first
    /// post-boot unlock (the poll loop must run without the user re-entering the login password),
    /// but never before first unlock and never synced off-device. The value is only ever passed
    /// as `kSecValueData`; it is never logged and never placed in an error (`WriteError` carries
    /// only the `OSStatus`). service/account are injectable so tests hit a THROWAWAY service,
    /// never the real one (`keychain-headless-prompt`). Trims paste artifacts defensively.
    @discardableResult
    public static func store(_ token: String, service: String = service, account: String = account) -> Result<Void, WriteError> {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Update first (the common "replace an old token" case), add if absent.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return .success(())
        case errSecItemNotFound:
            var addQuery = identity
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess ? .success(()) : .failure(.status(addStatus))
        default:
            return .failure(.status(updateStatus))
        }
    }

    /// Delete the stored token. An ALREADY-ABSENT item (`errSecItemNotFound`) is a benign
    /// no-op success (delete is idempotent) — the caller only cares that nothing remains.
    /// service/account injectable for the same throwaway-service test discipline as `store`.
    @discardableResult
    public static func delete(service: String = service, account: String = account) -> Result<Void, WriteError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return .success(())
        default:
            return .failure(.status(status))
        }
    }

    /// A non-sensitive description for logs/evidence — shape only, never the value.
    /// e.g. "ghp_•(40)" — prefix + length, no characters of the secret.
    public static func redacted(_ token: String) -> String {
        let prefix = token.split(separator: "_").first.map { "\($0)_" } ?? "?_"
        return "\(prefix)•(\(token.count))"
    }

    /// True for a classic PAT shape (`ghp_` + 36 = 40 chars). Fine-grained PATs are
    /// `github_pat_…` and are unsupported by the Notifications API. The length gate is
    /// `>= 40` (a full classic PAT), so a TRUNCATED 36–39-char paste is rejected here
    /// rather than passing the "classic PAT ✓" gate and then 401-ing at the API.
    public static func looksLikeClassicPAT(_ token: String) -> Bool {
        token.hasPrefix("ghp_") && token.count >= 40
    }
}
