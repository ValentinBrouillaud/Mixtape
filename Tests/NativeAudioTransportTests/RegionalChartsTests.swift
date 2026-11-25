import XCTest
@testable import NativeAudioTransport

final class RegionalChartsTests: XCTestCase {
    private func tile(_ id: String, _ title: String) -> [String: Any] {
        ["musicTwoRowItemRenderer": ["title": ["runs": [["text": title, "navigationEndpoint": ["browseEndpoint": ["browseId": id]]]]]]]
    }

    func testPeriodsStayDistinctAndMonthlyIsNeverSynthesized() {
        let directory = RegionalChartDirectory(json: ["contents": [
            tile("VLPLdaily", "Daily Top Music Videos - France"),
            tile("VLPLweekly", "Weekly Top Songs - France"),
            tile("VLPLunclassified", "Top Music Videos - France"),
            tile("VLPLmonthly", "Monthly fan selection"),
        ]])
        XCTAssertEqual(directory.choices(for: .weekly).map(\.id), ["PLweekly"])
        XCTAssertEqual(directory.choices(for: .current).map(\.id), ["PLdaily", "PLunclassified"])
        XCTAssertTrue(directory.choices(for: .monthly).isEmpty)
    }

    func testFrenchWeeklyTitlesAndDuplicateEndpoints() {
        let directory = RegionalChartDirectory(json: ["a": [
            tile("VLPLfr", "Top titres de la semaine - France"),
            tile("VLPLfr", "Top titres de la semaine - France"),
            tile("UC0123456789012345678901", "Artist"),
            tile("MPREalbum", "Album"),
        ]])
        XCTAssertEqual(directory.charts.count, 1)
        XCTAssertEqual(directory.choices(for: .weekly).first?.id, "PLfr")
    }

    func testMissingAndMalformedResponsesDoNotInventCharts() {
        XCTAssertTrue(RegionalChartDirectory(json: [:]).charts.isEmpty)
        XCTAssertTrue(RegionalChartDirectory(json: ["musicTwoRowItemRenderer": ["title": "bad"]]).charts.isEmpty)
    }

    func testGenericTop100IsWeeklyOnlyWithAssociatedSourceEvidence() {
        let json: [String: Any] = ["contents": [tile("VLPLfr", "Top 100 France"), tile("VLPLus", "Top 100 US")]]
        let directory = RegionalChartDirectory(json: json, periodEvidence: ["PLfr": "This week's ranking of music videos."])
        XCTAssertEqual(directory.choices(for: .weekly).map(\.id), ["PLfr"])
        XCTAssertEqual(directory.choices(for: .current).map(\.id), ["PLus"])
    }

    func testDescriptionShelfRetainsExplicitPeriodEvidence() {
        let json: [String: Any] = ["contents": [["musicDescriptionShelfRenderer": ["description": ["runs": [["text": "Updated weekly."]]]]]]]
        XCTAssertEqual(RegionalChartDirectory.sourceDescription(in: json), "Updated weekly.")
    }
}
