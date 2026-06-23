import Foundation

// MARK: - Alias sync (ADR-002a alias flywheel)
//
// Direct-to-Supabase, mirroring FoodReferenceService: the device pulls the whole
// canonical_alias table at boot (it is small — seeds + learned corrections) and
// folds it into the in-memory CanonicalIndex. Every HITL confirmation is POSTed
// back via the upsert_canonical_alias RPC, so the table is the cross-stream
// learning store.

actor CanonicalAliasService {
    static let shared = CanonicalAliasService()

    private let decoder = JSONDecoder()

    /// Pull all alias rows to seed/refresh the index. Failures are non-fatal —
    /// the cascade still works on lexical + fuzzy without aliases.
    func fetchAll() async -> [AliasEntry] {
        do {
            var components = URLComponents(
                url: AppConfig.supabaseURL.appendingPathComponent("rest/v1/canonical_alias"),
                resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "select", value: "*")]
            guard let url = components?.url else { return [] }

            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return try decoder.decode([AliasEntry].self, from: data)
        } catch {
            print("[CanonicalAliasService] fetchAll failed: \(error)")
            return []
        }
    }

    /// Write-on-confirm: persist a correction via the upsert RPC. Fire-and-forget
    /// from the caller's perspective — local index is already updated.
    func pushCorrection(_ entry: AliasEntry) async {
        do {
            let url = AppConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/upsert_canonical_alias")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

            let body: [String: Any?] = [
                "p_raw": entry.rawNormalized,
                "p_canonical": entry.canonicalName,
                "p_source": entry.source?.rawValue,
                "p_confidence": entry.confidence
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("[CanonicalAliasService] pushCorrection HTTP \(http.statusCode)")
            }
        } catch {
            print("[CanonicalAliasService] pushCorrection failed: \(error)")
        }
    }
}
