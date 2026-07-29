import Foundation
import Supabase

enum SupabaseConfig {
    private static let allowsInsecureHTTP: Bool = {
#if DEBUG
        return true
#else
        return false
#endif
    }()

    static let projectURL: URL? = validatedProjectURL(
        rawValue: value(infoKey: "BUDGETMATE_SUPABASE_URL", configKey: "SUPABASE_PROJECT_URL"),
        allowHTTP: allowsInsecureHTTP
    )

    static let publishableKey: String? = validatedPublishableKey(
        value(infoKey: "BUDGETMATE_SUPABASE_PUBLISHABLE_KEY", configKey: "SUPABASE_PUBLISHABLE_KEY")
    )

    static func validatedProjectURL(rawValue: String?, allowHTTP: Bool) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              !rawValue.contains("$("),
              !rawValue.localizedCaseInsensitiveContains("your-project"),
              !rawValue.localizedCaseInsensitiveContains("configuration.invalid") else {
            return nil
        }

        // The config stores the host without a scheme because xcconfig treats
        // "//" as a comment. Add HTTPS back for host-only values, while still
        // rejecting explicit HTTP in Release.
        let normalized = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let url = URL(string: normalized),
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.path == "" || url.path == "/",
              url.query == nil,
              url.fragment == nil,
              url.scheme == "https" || (allowHTTP && url.scheme == "http"),
              (!isLocalHost(host) || allowHTTP),
              !isPlaceholderHost(host) else {
            return nil
        }
        return url
    }

    static func validatedPublishableKey(_ rawKey: String?) -> String? {
        guard let rawKey else { return nil }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.contains("$("),
              !key.localizedCaseInsensitiveContains("your-publishable-key"),
              !key.localizedCaseInsensitiveContains("missing-publishable-key"),
              !key.localizedCaseInsensitiveContains("placeholder") else { return nil }

        return key
    }

    static var isConfigured: Bool {
        projectURL != nil && publishableKey != nil
    }

    static var userFacingConfigurationMessage: String {
#if DEBUG
        return "This build is missing its Supabase connection. Add SUPABASE_PROJECT_URL and SUPABASE_PUBLISHABLE_KEY to BudgetMate/Config/Supabase.local.xcconfig, then rebuild."
#else
        return "BudgetMate can't connect to its cloud service in this build. Please update the app or contact support."
#endif
    }

    private static func value(infoKey: String, configKey: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return bundledLocalConfig()[configKey]
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost == "localhost" ||
            normalizedHost == "127.0.0.1" ||
            normalizedHost == "::1" ||
            normalizedHost == "[::1]"
    }

    private static func isPlaceholderHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost == "example.com" ||
            normalizedHost == "example.invalid" ||
            normalizedHost.hasSuffix(".example.com") ||
            normalizedHost.hasSuffix(".example.invalid")
    }

    private static func bundledLocalConfig() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Supabase.local", withExtension: "xcconfig"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2,
                      !parts[0].isEmpty,
                      !parts[0].hasPrefix("//") else {
                    return
                }

                result[parts[0]] = parts[1].replacingOccurrences(of: ":/$()/", with: "://")
            }
    }
}

enum SupabaseClientProvider {
    // Keep dependency construction non-fatal so a misconfigured development or
    // release build can present an actionable screen instead of terminating at
    // launch. AuthSessionStore prevents this placeholder client from making a
    // request while configuration is absent.
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.projectURL ?? URL(string: "https://configuration.invalid")!,
        supabaseKey: SupabaseConfig.publishableKey ?? "missing-publishable-key"
    )
}
