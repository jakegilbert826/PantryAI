import Foundation

/// Talks to Gemini directly using the `generativelanguage.googleapis.com` REST
/// API. The protocol means it can be swapped for a backend-routed variant
/// later without touching call sites.
final class GeminiService: GeminiServiceProtocol {
    private let keychain = KeychainService()

    // MARK: Scan (vision)

    func scanInventory(imageData: Data) async throws -> [ScannedItem] {
        let apiKey = try requireKey()
        let url = AppConfig.geminiBaseURL
            .appendingPathComponent("models/\(AppConfig.geminiModel):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": Self.scanPrompt],
                    ["inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString(),
                    ]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp, data)
        return try decodeScanItems(from: try extractText(from: data))
    }

    func scanReceipt(imageData: Data) async throws -> [ScannedItem] {
        let apiKey = try requireKey()
        let url = AppConfig.geminiBaseURL
            .appendingPathComponent("models/\(AppConfig.geminiModel):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": Self.receiptPrompt],
                    ["inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString(),
                    ]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json",
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp, data)
        return try decodeReceiptItems(from: try extractText(from: data))
    }

    // MARK: Recipes

    func generateRecipes(
        inventory: [InventoryItem],
        preferences: [RecipePreferenceSnapshot]
    ) async throws -> [RecipeSuggestion] {
        let apiKey = try requireKey()
        let url = AppConfig.geminiBaseURL
            .appendingPathComponent("models/\(AppConfig.geminiModel):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": Self.recipePrompt(inventory: inventory, preferences: preferences)]]
            ]],
            "generationConfig": [
                "temperature": 0.6,
                "responseMimeType": "application/json",
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp, data)
        return try decodeRecipes(from: try extractText(from: data))
    }

    // MARK: Recipe detail (streaming)

    func streamRecipeDetail(
        recipe: String,
        inventory: [InventoryItem]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try requireKey()
        let baseURL = AppConfig.geminiBaseURL
            .appendingPathComponent("models/\(AppConfig.geminiModel):streamGenerateContent")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components?.url else {
            throw PantryError.network("could not build streaming URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": Self.recipeDetailPrompt(recipe: recipe, inventory: inventory)]]
            ]],
            "generationConfig": ["temperature": 0.5]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try ensureOK(resp, nil)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty else { continue }
                        if let token = try? Self.parseStreamChunk(payload), !token.isEmpty {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: Chat recipe (streaming)

    func streamChatRecipe(
        history: [ChatTurn],
        inventory: [InventoryItem]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try requireKey()
        let baseURL = AppConfig.geminiBaseURL
            .appendingPathComponent("models/\(AppConfig.geminiModel):streamGenerateContent")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components?.url else {
            throw PantryError.network("could not build streaming URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let window = history.suffix(10)
        let contents: [[String: Any]] = window.map { turn in
            ["role": turn.role == .user ? "user" : "model",
             "parts": [["text": turn.text]]]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": Self.chatSystemInstruction(inventory: inventory)]]],
            "contents": contents,
            "generationConfig": ["temperature": 0.7]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try ensureOK(resp, nil)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty else { continue }
                        if let token = try? Self.parseStreamChunk(payload), !token.isEmpty {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: Helpers

    private func requireKey() throws -> String {
        guard let key = keychain.get(.geminiAPIKey), !key.isEmpty else {
            throw PantryError.missingAPIKey
        }
        return key
    }

    private func ensureOK(_ resp: URLResponse, _ data: Data?) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw PantryError.network("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw PantryError.geminiRefused("HTTP \(http.statusCode) — \(body.prefix(200))")
        }
    }

    private func extractText(from data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw PantryError.decoding("Gemini response shape unexpected")
        }
        return text
    }

    private func decodeScanItems(from text: String) throws -> [ScannedItem] {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8) else { throw PantryError.decoding("non-utf8") }
        struct Raw: Decodable {
            let name: String
            let canonicalName: String?
            let brandName: String?
            let barcode: String?
            let packagingCategory: String?
            let foodCategory: String?
            let storageLocation: String?
            let measureType: String?
            let measureValue: Double?
            let measureUnit: String?
            let openedAtEstimated: Bool?
            let confidence: Double

            enum CodingKeys: String, CodingKey {
                case name
                case canonicalName = "canonical_name"
                case brandName = "brand_name"
                case barcode
                case packagingCategory = "packaging_category"
                case foodCategory = "food_category"
                case storageLocation = "storage_location"
                case measureType = "measure_type"
                case measureValue = "measure_value"
                case measureUnit = "measure_unit"
                case openedAtEstimated = "opened_at_estimated"
                case confidence
            }
        }
        let raws = try JSONDecoder().decode([Raw].self, from: data)
        return raws.map {
            ScannedItem(
                name: $0.name,
                canonicalName: $0.canonicalName ?? $0.name,
                foodCategory: $0.foodCategory.flatMap(FoodCategory.init) ?? .dryGoods,
                brandName: $0.brandName,
                measureValue: $0.measureValue ?? 0,
                measureUnit: .from($0.measureUnit),
                confidence: $0.confidence
            )
        }
    }

    private func decodeReceiptItems(from text: String) throws -> [ScannedItem] {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8) else { throw PantryError.decoding("non-utf8") }
        struct Raw: Decodable {
            let name: String
            let category: String
            let brand: String?
            let quantity: Double
            let unit: String?
            let confidence: Double
        }
        let raws = try JSONDecoder().decode([Raw].self, from: data)
        return raws.map {
            ScannedItem(
                name: $0.name,
                canonicalName: $0.name,
                foodCategory: FoodCategory(rawValue: $0.category) ?? .dryGoods,
                brandName: $0.brand,
                measureValue: $0.quantity,
                measureUnit: .from($0.unit),
                confidence: $0.confidence
            )
        }
    }

    private func decodeRecipes(from text: String) throws -> [RecipeSuggestion] {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8) else { throw PantryError.decoding("non-utf8") }
        return try JSONDecoder().decode([RecipeSuggestion].self, from: data)
    }

    private func stripCodeFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = String(t.drop(while: { $0 != "\n" })).trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t
    }

    private static func parseStreamChunk(_ buffer: String) throws -> String? {
        guard let data = buffer.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        return nil
    }
}

// MARK: - Prompts

extension GeminiService {
    static let receiptPrompt = """
    You are a grocery receipt parser. The image shows a paper or digital grocery receipt.

    Extract all food and grocery items purchased. Skip non-food items (household supplies, fees, discounts, taxes, loyalty points).

    Return ONLY a JSON array with no markdown, no explanation. Each object must have:
    {
      "name": string,           // clean product name, expand common abbreviations (e.g. "CHKN" → "Chicken", "ORG" → "Organic")
      "category": string,       // one of: fresh_produce, dairy, meat, fish, frozen_goods, dry_goods, condiments, beverages, snacks
      "brand": string | null,   // brand if identifiable from the receipt line, otherwise null
      "quantity": number,       // units purchased (e.g. 2 for a line showing "2 x ..."), default 1
      "unit": string | null,    // "g", "ml", "units", "kg", "oz", "lb" or null
      "confidence": number      // 0.0–1.0; lower if OCR text was unclear or abbreviation was ambiguous
    }

    If the same item appears more than once, merge and sum quantities.
    If you cannot identify an item as food or grocery, omit it.
    """

    static let scanPrompt = """
    You are a kitchen inventory scanner. Analyse this image and return ONLY a JSON array. No markdown, no explanation.

    Each object must have:
    {
      "name": string,
      "canonical_name": string,       // normalised lowercase, no brand e.g. "free range egg"
      "brand_name": string | null,
      "barcode": string | null,       // if visible on packaging
      "packaging_category": string,   // one of: fresh, canned, dried, frozen, beverage, condiment
      "food_category": string,        // one of: fresh_produce, dairy, meat, fish, frozen_goods, dry_goods, condiments, beverages, snacks
      "storage_location": string,     // one of: fridge, freezer, pantry
      "measure_type": string,         // one of: weight, volume, count
      "measure_value": number | null, // null if cannot be determined — always in base units (grams for weight, ml for volume)
      "measure_unit": string | null,  // one of: g, ml, unit — always use base units, never kg or l
      "opened_at_estimated": bool,    // true if packaging appears opened or partially used
      "confidence": number            // your detection confidence 0.0–1.0
    }

    Rules:
    - Always express weight in grams (g) and volume in millilitres (ml) — never use kg or l
    - If measure_value cannot be determined from the image, return null — do not guess
    - If an item appears partially used, reflect that in measure_value (e.g. half a 400g can = 200)
    - Omit items you cannot identify with reasonable confidence
    - Never return measure_value: 1.0 as a proxy for "full" — return the actual value or null
    """

    static func recipePrompt(inventory: [InventoryItem], preferences: [RecipePreferenceSnapshot]) -> String {
        let inv = inventory.map { item -> [String: Any] in
            let qty: Any = item.measureValue.map { $0 > 0 ? ($0 as Any) : ("unknown" as Any) } ?? ("unknown" as Any)
            return [
                "name": item.name,
                "category": item.foodCategory.rawValue,
                "confidence": item.currentConfidence,
                "quantity": qty,
            ]
        }
        let prefs = preferences.map {
            ["name": $0.recipeName, "liked": $0.liked] as [String: Any]
        }
        let invJSON = (try? JSONSerialization.data(withJSONObject: inv)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let prefJSON = (try? JSONSerialization.data(withJSONObject: prefs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        You are a recipe assistant. The user's current pantry inventory (with confidence scores) is:
        \(invJSON)

        Their food preferences (liked/disliked): \(prefJSON)

        Suggest 5 recipes they can make. Prioritise:
        1. Recipes using items with low confidence (expiring soon)
        2. Recipes matching their preferences
        3. Recipes with the highest ingredient coverage from current inventory

        Some items have quantity "unknown" — this means the amount was not recorded, not that none is left.
        Never expose "unknown" literally in recipe names, ingredient lists, or descriptions.
        Instead use natural phrasing, e.g. "I think you have some pesto — use it here" or "eggs (if you have any left)".

        Return ONLY a JSON array:
        [{
          "name": string,
          "coveragePercent": number,
          "missingIngredients": [string],
          "requiredIngredients": [string]
        }]
        """
    }

    static func chatSystemInstruction(inventory: [InventoryItem]) -> String {
        let inv = inventory.isEmpty
            ? "The pantry is currently empty."
            : "The user's pantry contains: " + inventory.map { "\($0.name) (\(Int($0.currentConfidence * 100))% left)" }.joined(separator: ", ") + "."
        return """
        You are Pip, a friendly kitchen assistant. \(inv)
        Help the user with recipe requests and cooking questions across the conversation, using pantry items where possible. If key items are missing, note what to buy.
        Format recipes as markdown: a short intro, an ingredients list with quantities, then numbered cooking steps.
        Keep it practical and under 30 minutes where possible.

        At the very end of EVERY response, after all other content, append this exact block:
        ---JSON---
        {"remove": [], "add": []}

        Populate "remove" with the exact names of any pantry items the user says they don't have or want removed. Populate "add" with the exact names of any items the user says they've just bought or want added. Always include the block even when both arrays are empty. Do not include any text after the JSON block.
        """
    }

    static func recipeDetailPrompt(recipe: String, inventory: [InventoryItem]) -> String {
        let inv = inventory.map { "\($0.name) (\(Int($0.currentConfidence * 100))% left)" }.joined(separator: ", ")
        return """
        Write a clear, concise recipe for "\(recipe)". Use what the user already has where possible: \(inv).
        Format the response as markdown with a short intro, an ingredients list with quantities, and numbered steps.
        Keep total time under 30 minutes if possible. Don't pad with culinary backstory.
        """
    }
}
