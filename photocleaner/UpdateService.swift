import Supabase
import Foundation

@MainActor
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://uetswhrdkmokxtnzsaeq.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVldHN3aHJka21va3h0bnpzYWVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM5MTQ1NjcsImV4cCI6MjA1OTQ5MDU2N30.1ceVlgsfTFJn6EkTitEsH97e6SAatJWsh6gHu8c25z4"
    )

    @Published var shouldForceUpdate = false
    @Published var shouldShowOptionalUpdate = false
    @Published var updateNotes: String?

    private let platform = "ios"
    private let dismissedVersionKey = "dismissedVersion"
    
    var dismissedVersion: String {
            get {
                UserDefaults.standard.string(forKey: dismissedVersionKey) ?? ""
            }
            set {
                UserDefaults.standard.set(newValue, forKey: dismissedVersionKey)
            }
        }
    // MARK: - Main logic
        func checkAppVersion() async {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

            do {
                // Step 1: Check current version
                let currentResponse: PostgrestResponse<[AppVersion]> = try await client
                    .from("app_versions")
                    .select("*")
                    .eq("platform", value: platform)
                    .eq("version", value: currentVersion)
                    .limit(1)
                    .execute()

                guard let currentInfo = currentResponse.value.first else {
                    print("❌ No current version info found for \(currentVersion)")
                    return
                }

                if !currentInfo.is_valid {
                    shouldForceUpdate = true
                    updateNotes = currentInfo.notes
                    return
                }

                // Step 2: Optional update check
                if !currentInfo.is_latest && dismissedVersion != currentInfo.version {
                    let latestResponse: PostgrestResponse<[AppVersion]> = try await client
                        .from("app_versions")
                        .select("*")
                        .eq("platform", value: platform)
                        .eq("is_latest", value: true)
                        .limit(1)
                        .execute()

                    if let latest = latestResponse.value.first {
                        shouldShowOptionalUpdate = true
                        updateNotes = latest.notes
                    }
                }

            } catch {
                print("❌ Supabase version check failed: \(error)")
            }
        }
}
