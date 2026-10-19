import XCTest
@testable import Zenmanage

final class ErrorsTests: XCTestCase {
    private let cases: [(error: ZenmanageError, message: String, code: Int)] = [
        (.configuration("bad config"), "bad config", 1001),
        (.evaluation("bad evaluation"), "bad evaluation", 1002),
        (.fetchRules("bad fetch"), "bad fetch", 1003),
        (.invalidRules("bad rules"), "bad rules", 1004),
        (.cache("bad cache"), "bad cache", 1005),
    ]

    func testErrorDescriptionIsTheMessage() {
        for (error, message, _) in cases {
            XCTAssertEqual(error.errorDescription, message)
            XCTAssertEqual(error.localizedDescription, message)
        }
    }

    func testEachCaseMapsToADistinctNSErrorCode() {
        for (error, _, code) in cases {
            let nsError = error.nsError

            XCTAssertEqual(nsError.domain, "com.zenmanage.swift")
            XCTAssertEqual(nsError.code, code)
            XCTAssertEqual(nsError.localizedDescription, error.errorDescription)
        }

        XCTAssertEqual(Set(cases.map { $0.error.nsError.code }).count, cases.count)
    }

    func testZenmanageErrorsBridgeThroughTheErrorExtension() {
        let error: Error = ZenmanageError.evaluation("nope")

        XCTAssertEqual(error.zenmanageNSError.code, 1002)
        XCTAssertEqual(error.zenmanageNSError.domain, "com.zenmanage.swift")
    }

    func testForeignErrorsPassThroughUnchanged() {
        let foreign = NSError(domain: "other.domain", code: 42, userInfo: nil)

        XCTAssertEqual(foreign.zenmanageNSError.domain, "other.domain")
        XCTAssertEqual(foreign.zenmanageNSError.code, 42)
    }

    func testErrorsAreEquatable() {
        XCTAssertEqual(ZenmanageError.cache("x"), ZenmanageError.cache("x"))
        XCTAssertNotEqual(ZenmanageError.cache("x"), ZenmanageError.cache("y"))
        XCTAssertNotEqual(ZenmanageError.cache("x"), ZenmanageError.fetchRules("x"))
    }
}
