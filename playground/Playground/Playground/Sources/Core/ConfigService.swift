import Foundation
import Combine

/// Two-tier configuration service: user overrides + defaults
/// Apps can define defaults, users can override them
class ConfigService: ObservableObject {
    static let shared = ConfigService()

    // User overrides (persistent via UserDefaults)
    private let userDefaults = UserDefaults.standard
    private let userOverridesPrefix = "config."

    // Default values (in-memory, defined by apps)
    private var defaults: [String: Any] = [:]

    // Change notifications
    @Published private(set) var configVersion: Int = 0

    private init() {
        // Initialize with common LLM defaults
        defineConfig(key: "llm.base_url", value: "https://api.openai.com/v1")
        defineConfig(key: "llm.model", value: "gpt-4o-mini")
        defineConfig(key: "llm.max_tokens", value: 1024)
        defineConfig(key: "llm.temperature", value: 0.7)

        // High-tier model defaults (for complex tasks)
        defineConfig(key: "llm.high.base_url", value: "https://api.openai.com/v1")
        defineConfig(key: "llm.high.model", value: "gpt-4")
        defineConfig(key: "llm.high.max_tokens", value: 4096)
        defineConfig(key: "llm.high.temperature", value: 0.7)
    }

    // MARK: - Define Defaults

    /// Define a default config value (in-memory only)
    /// Apps call this in their onInit() method
    func defineConfig(key: String, value: Any) {
        defaults[key] = value
    }

    /// Define multiple defaults at once
    func defineConfigs(_ configs: [String: Any]) {
        for (key, value) in configs {
            defaults[key] = value
        }
    }

    // MARK: - Get Config

    /// Get config value with two-tier fallback: user override → default
    func getConfig<T>(key: String) -> T? {
        // First check user overrides
        if let override = getUserOverride(key: key) as? T {
            return override
        }

        // Fall back to defaults
        return defaults[key] as? T
    }

    /// Get config value with provided fallback
    func getConfig<T>(key: String, default fallback: T) -> T {
        return getConfig(key: key) ?? fallback
    }

    /// Get string config
    func getString(key: String, default fallback: String = "") -> String {
        return getConfig(key: key, default: fallback)
    }

    /// Get int config
    func getInt(key: String, default fallback: Int = 0) -> Int {
        return getConfig(key: key, default: fallback)
    }

    /// Get double config
    func getDouble(key: String, default fallback: Double = 0.0) -> Double {
        return getConfig(key: key, default: fallback)
    }

    /// Get bool config
    func getBool(key: String, default fallback: Bool = false) -> Bool {
        return getConfig(key: key, default: fallback)
    }

    // MARK: - Set Config (User Overrides)

    /// Set a user override (persists to UserDefaults)
    func setConfig<T>(key: String, value: T?) {
        let prefixedKey = userOverridesPrefix + key

        if let value = value {
            userDefaults.set(value, forKey: prefixedKey)
        } else {
            userDefaults.removeObject(forKey: prefixedKey)
        }

        // Notify observers
        configVersion += 1
    }

    /// Set multiple config values at once
    func setConfigs(_ configs: [String: Any?]) {
        for (key, value) in configs {
            let prefixedKey = userOverridesPrefix + key
            if let value = value {
                userDefaults.set(value, forKey: prefixedKey)
            } else {
                userDefaults.removeObject(forKey: prefixedKey)
            }
        }

        configVersion += 1
    }

    /// Clear a user override (reverts to default)
    func clearConfig(key: String) {
        setConfig(key: key, value: nil as String?)
    }

    // MARK: - Private Helpers

    private func getUserOverride(key: String) -> Any? {
        let prefixedKey = userOverridesPrefix + key
        return userDefaults.object(forKey: prefixedKey)
    }

    // MARK: - Bulk Operations

    /// Get all config keys (defaults + overrides)
    func getAllKeys() -> [String] {
        var keys = Set(defaults.keys)

        // Add override keys (removing prefix)
        let overrideKeys = userDefaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(userOverridesPrefix) }
            .map { String($0.dropFirst(userOverridesPrefix.count)) }
        keys.formUnion(overrideKeys)

        return Array(keys).sorted()
    }

    /// Get all config values as dictionary
    func getAllConfigs() -> [String: Any] {
        var configs: [String: Any] = [:]

        for key in getAllKeys() {
            if let value: Any = getConfig(key: key) {
                configs[key] = value
            }
        }

        return configs
    }

    /// Check if a key has a user override
    func hasOverride(key: String) -> Bool {
        return getUserOverride(key: key) != nil
    }

    /// Clear all user overrides
    func clearAllOverrides() {
        let keys = userDefaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(userOverridesPrefix) }

        for key in keys {
            userDefaults.removeObject(forKey: key)
        }

        configVersion += 1
    }
}

// MARK: - App-Scoped Config

extension ConfigService {
    /// Get app-scoped config (prefixed with appId)
    func getAppConfig<T>(appId: String, key: String) -> T? {
        return getConfig(key: "\(appId).\(key)")
    }

    /// Set app-scoped config
    func setAppConfig<T>(appId: String, key: String, value: T?) {
        setConfig(key: "\(appId).\(key)", value: value)
    }

    /// Define app-scoped default
    func defineAppConfig(appId: String, key: String, value: Any) {
        defineConfig(key: "\(appId).\(key)", value: value)
    }
}
