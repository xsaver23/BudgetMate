import Foundation
import Supabase

enum SupabaseConfig {
    static let projectURL: URL = {
        guard let rawValue = value(infoKey: "BUDGETMATE_SUPABASE_URL", configKey: "SUPABASE_PROJECT_URL"),
              let url = URL(string: rawValue),
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preconditionFailure("Missing BUDGETMATE_SUPABASE_URL. Add it to BudgetMate/Config/Supabase.local.xcconfig.")
        }

        return url
    }()

    static let publishableKey: String = {
        guard let key = value(infoKey: "BUDGETMATE_SUPABASE_PUBLISHABLE_KEY", configKey: "SUPABASE_PUBLISHABLE_KEY"),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preconditionFailure("Missing BUDGETMATE_SUPABASE_PUBLISHABLE_KEY. Add it to BudgetMate/Config/Supabase.local.xcconfig.")
        }

        return key
    }()

    private static func value(infoKey: String, configKey: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return bundledLocalConfig()[configKey]
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
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.projectURL,
        supabaseKey: SupabaseConfig.publishableKey
    )
}
