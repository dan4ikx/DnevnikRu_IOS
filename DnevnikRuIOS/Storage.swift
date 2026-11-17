import Foundation
import CryptoKit
import Security

enum VaultError: LocalizedError {
    case unavailable
    case corrupt
    var errorDescription: String? {
        switch self {
        case .unavailable: "Не удалось получить защищённое хранилище."
        case .corrupt: "Повреждены сохранённые данные. Попробуйте очистить кэш."
        }
    }
}
enum KeychainBox {
    private static let service = "ru.dnkx.myschool.ios"
    static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var data: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &data) == errSecSuccess ? data as? Data : nil
    }
    static func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var inserted = query
            attributes.forEach { inserted[$0.key] = $0.value }
            guard SecItemAdd(inserted as CFDictionary, nil) == errSecSuccess else { throw VaultError.unavailable }
        } else if status != errSecSuccess { throw VaultError.unavailable }
    }
    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
struct SessionCookie: Codable, Hashable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let expires: Date?
    init?(_ cookie: HTTPCookie) {
        let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host == "dnevnik.ru" || host.hasSuffix(".dnevnik.ru") else { return nil }
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        secure = cookie.isSecure
        httpOnly = (cookie.properties?[HTTPCookiePropertyKey(rawValue: "HttpOnly")] as? String)?.lowercased() == "true"
        expires = cookie.expiresDate
    }
    var asCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
            .secure: secure ? "TRUE" : "FALSE"
        ]
        if httpOnly { properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}
struct SessionArchive: Codable {
    var cookies: [SessionCookie]
    var principal: String
    var userAgent: String
}
struct AccountEntry: Codable, Hashable, Identifiable {
    var id: String
    var label: String
}
struct AccountCatalog: Codable {
    var entries: [AccountEntry] = [AccountEntry(id: "default", label: "Аккаунт 1")]
    var selected = "default"
    var current: String { entries.contains { $0.id == selected } ? selected : entries.first?.id ?? "default" }
}
actor SecureVault {
    static let shared = SecureVault()
    private let directory: URL
    private let key: SymmetricKey
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("MySchool", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data: Data
        if let existing = KeychainBox.read("vault-key"), existing.count == 32 {
            data = existing
        } else {
            var random = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                fatalError("Unable to generate encryption key")
            }
            data = Data(random)
            try? KeychainBox.write(data, account: "vault-key")
        }
        key = SymmetricKey(data: data)
    }
    private func file(_ account: String, _ name: String) -> URL {
        let raw = account + "_" + name
        let safe = String(raw.map { c in
            c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_") ? c : "_"
        })
        return directory.appendingPathComponent(safe + ".cache")
    }
    func read<T: Decodable>(_ type: T.Type, name: String, account: String = "shared") throws -> T? {
        let url = file(account, name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let raw = try Data(contentsOf: url)
        guard let box = try? AES.GCM.SealedBox(combined: raw),
              let opened = try? AES.GCM.open(box, using: key) else { throw VaultError.corrupt }
        return try decoder.decode(type, from: opened)
    }
    func save<T: Encodable>(_ value: T, name: String, account: String = "shared") throws {
        let bytes = try encoder.encode(value)
        guard let payload = try AES.GCM.seal(bytes, using: key).combined else { throw VaultError.unavailable }
        try payload.write(to: file(account, name), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    func remove(name: String, account: String) {
        try? FileManager.default.removeItem(at: file(account, name))
    }
    func erase(account: String) {
        let prefix = file(account, "").deletingPathExtension().lastPathComponent
        if let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: entry)
            }
        }
        KeychainBox.remove("session.\(account)")
    }
    func session(for account: String) -> SessionArchive? {
        guard let raw = KeychainBox.read("session.\(account)") else { return nil }
        return try? decoder.decode(SessionArchive.self, from: raw)
    }
    func setSession(_ value: SessionArchive?, for account: String) throws {
        guard let value else { KeychainBox.remove("session.\(account)"); return }
        try KeychainBox.write(try encoder.encode(value), account: "session.\(account)")
    }
    func catalog() -> AccountCatalog {
        (try? read(AccountCatalog.self, name: "accounts")) ?? AccountCatalog()
    }
    func saveCatalog(_ catalog: AccountCatalog) throws { try save(catalog, name: "accounts") }
}
