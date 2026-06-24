import XCTest
@testable import PantryAI

final class ReceiptLineParserTests: XCTestCase {

    private func names(_ texts: [String]) -> [String] {
        ReceiptLineParser.parse(texts).map(\.name)
    }

    // MARK: - Noise filtering

    func testDropsTotalsAndPaymentLines() {
        let lines = [
            "WHOLE MILK 1.15",
            "SUBTOTAL 4.30",
            "TOTAL 4.30",
            "VISA DEBIT 4.30",
            "CHANGE 0.00",
            "VAT NO 123456789",
        ]
        XCTAssertEqual(names(lines), ["WHOLE MILK"])
    }

    func testDropsHeadersDatesAndPriceOnlyLines() {
        let lines = [
            "TESCO STORES LTD",
            "12/03/2026 14:22",
            "0161 123 4567",
            "1.30",
            "CHEDDAR 2.00",
        ]
        XCTAssertEqual(names(lines), ["CHEDDAR"])
    }

    func testDropsLinesWithTooFewLetters() {
        XCTAssertTrue(names(["X 1.00", "** 2.50", "A"]).isEmpty)
    }

    func testDropsStoreDomainsAndUrls() {
        let lines = [
            "woolworths.com",
            "www.tesco.com",
            "https://coles.com.au",
            "shop online at sainsburys.co.uk",
            "MILK 1.15",
        ]
        XCTAssertEqual(names(lines), ["MILK"])
    }

    func testDropsUnitPriceAndMetadataLines() {
        // The classic false positives: unit-rate headers under produce lines.
        let lines = [
            "BANANAS",
            "NET@/kg",
            "NET @ $2.50/kg",
            "PER KG",
            "EACH",
            "0.452 kg NET",
        ]
        XCTAssertEqual(names(lines), ["BANANAS"])
    }

    func testDropsLoyaltyAndTaxFurniture() {
        let lines = [
            "EVERYDAY REWARDS",
            "ABN 88 000 014 675",
            "GST 1.20",
            "TAX INVOICE",
            "EFTPOS",
            "BREAD 2.00",
        ]
        XCTAssertEqual(names(lines), ["BREAD"])
    }

    // MARK: - Body-boundary anchoring

    func testDropsStoreNameSloganAndAddressHeader() {
        // None of these carry a noise keyword or a price, so per-line filtering
        // alone leaks them; header trimming (above the first priced line) cuts them.
        let lines = [
            "WAITROSE & PARTNERS",
            "12 HIGH STREET",
            "FRESH FOOD FOR LESS",
            "CHEDDAR 2.00",
            "BREAD 1.10",
        ]
        XCTAssertEqual(names(lines), ["CHEDDAR", "BREAD"])
    }

    func testDropsPostTotalVatSummary() {
        // A VAT breakdown after TOTAL has letters + a price + no keyword; only the
        // footer cut (everything from the first totals line down) removes it.
        let lines = [
            "MILK 1.15",
            "BREAD 1.10",
            "TOTAL 2.25",
            "STANDARD RATE GOODS 5.00",
            "VAT 0.00",
        ]
        XCTAssertEqual(names(lines), ["MILK", "BREAD"])
    }

    func testCutsItemsBelowSubtotalPhrase() {
        // "SUB TOTAL" (two words) marks the footer; the trailing survey line would
        // otherwise leak (no noise token).
        let lines = [
            "EGGS 2.00",
            "SUB TOTAL 2.00",
            "CARD PAYMENT 2.00",
            "SURVEY AT FEEDBACK 5.00",
        ]
        XCTAssertEqual(names(lines), ["EGGS"])
    }

    func testProduceWithoutAnyPriceIsKept() {
        // No line carries a trailing price → header trim must not fire and eat the
        // items. Guards the all-produce receipt against over-trimming.
        let lines = ["BANANAS", "LOOSE TOMATOES", "PER KG"]
        XCTAssertEqual(names(lines), ["BANANAS", "LOOSE TOMATOES"])
    }

    func testKeepsRealItemWithPromoWordInName() {
        // "SPECIAL" is a soft stopword, but "SPECIAL K" has a real noun token.
        XCTAssertEqual(names(["SPECIAL K 3.50"]), ["SPECIAL K"])
    }

    // MARK: - Name + price

    func testExtractsNameAndStripsTrailingPrice() {
        let parsed = ReceiptLineParser.parse(["HEINZ BEANS 0.85"])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].name, "HEINZ BEANS")
        XCTAssertEqual(parsed[0].price, 0.85)
    }

    func testHandlesCurrencySymbolAndVatCode() {
        let parsed = ReceiptLineParser.parse(["BUTTER £1.45 A"])
        XCTAssertEqual(parsed[0].name, "BUTTER")
        XCTAssertEqual(parsed[0].price, 1.45)
    }

    func testPriceRaisesConfidence() {
        let withPrice = ReceiptLineParser.parse(["BANANAS 0.95"])[0].confidence
        let noPrice = ReceiptLineParser.parse(["BANANAS"])[0].confidence
        XCTAssertGreaterThan(withPrice, noPrice)
    }

    // MARK: - Measure parsing

    func testParsesNetWeightToCanonicalGrams() {
        let parsed = ReceiptLineParser.parse(["CHICKEN BREAST 1.2KG 5.50"])
        XCTAssertEqual(parsed[0].measureUnit, .g)
        XCTAssertEqual(parsed[0].measureValue, 1200, accuracy: 0.01)
    }

    func testParsesVolumeToCanonicalMillilitres() {
        let parsed = ReceiptLineParser.parse(["ORANGE JUICE 1L 1.10"])
        XCTAssertEqual(parsed[0].measureUnit, .ml)
        XCTAssertEqual(parsed[0].measureValue, 1000, accuracy: 0.01)
    }

    func testTrailingPriceNotMistakenForWeight() {
        // "1.15" at the end is a price, not 1.15 of anything.
        let parsed = ReceiptLineParser.parse(["WHOLE MILK 1.15"])
        XCTAssertEqual(parsed[0].measureValue, 0)
        XCTAssertEqual(parsed[0].measureUnit, .unit)
        XCTAssertEqual(parsed[0].name, "WHOLE MILK")
    }

    func testParsesMultipackCount() {
        let parsed = ReceiptLineParser.parse(["2 @ 0.85 APPLES"])
        XCTAssertEqual(parsed[0].measureValue, 2)
        XCTAssertEqual(parsed[0].measureUnit, .unit)
        XCTAssertEqual(parsed[0].name, "APPLES")
    }

    func testLeadingQuantityStrippedFromName() {
        let parsed = ReceiptLineParser.parse(["3 ONIONS 0.90"])
        XCTAssertEqual(parsed[0].name, "ONIONS")
    }

    // MARK: - Ordering / confidence propagation

    func testPreservesReceiptOrder() {
        let lines = ["MILK 1.15", "EGGS 2.00", "BREAD 1.10"]
        XCTAssertEqual(names(lines), ["MILK", "EGGS", "BREAD"])
    }

    func testOCRConfidenceFoldedIn() {
        let low = ReceiptLineParser.parse([ReceiptOCRLine(text: "MILK 1.15", confidence: 0.4)])
        let high = ReceiptLineParser.parse([ReceiptOCRLine(text: "MILK 1.15", confidence: 1.0)])
        XCTAssertLessThan(low[0].confidence, high[0].confidence)
    }
}
