import Foundation
import Supabase

enum SupabaseConfig {
    static let projectURL = URL(string: "https://YOUR-SUPABASE-PROJECT.supabase.co")!
    static let publishableKey = "sb_publishable_REDACTED"
}

enum SupabaseClientProvider {
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.projectURL,
        supabaseKey: SupabaseConfig.publishableKey
    )
}
