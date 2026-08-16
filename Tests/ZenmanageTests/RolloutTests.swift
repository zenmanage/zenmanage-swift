import XCTest
@testable import Zenmanage

final class RolloutTests: XCTestCase {
    func testCRC32BMatchesKnownValue() {
        XCTAssertEqual(RolloutBucketer.crc32b("abc"), 0x352441C2)
    }

    func testRolloutBucketingIsDeterministicAndMonotonic() throws {
        let userID = "user-rollout-1"
        let salt = "rollout-salt"

        let tenPercent = try RolloutBucketer.isInBucket(salt: salt, contextIdentifier: userID, percentage: 10)
        let fiftyPercent = try RolloutBucketer.isInBucket(salt: salt, contextIdentifier: userID, percentage: 50)
        let hundredPercent = try RolloutBucketer.isInBucket(salt: salt, contextIdentifier: userID, percentage: 100)

        XCTAssertEqual(tenPercent, try RolloutBucketer.isInBucket(salt: salt, contextIdentifier: userID, percentage: 10))
        XCTAssertTrue(!tenPercent || fiftyPercent)
        XCTAssertTrue(hundredPercent)
    }
}