import Foundation
import Zenmanage

@main
enum SimpleFlagsExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            let booleanFlag = try await sdk.flags().single("example-boolean-flag", defaultValue: false)
            print("Boolean flag enabled: \(booleanFlag.isEnabled())")

            let stringFlag = try await sdk.flags().single("example-string-flag", defaultValue: "default-value")
            print("String flag: \(stringFlag.asString())")

            let numberFlag = try await sdk.flags().single("example-number-flag", defaultValue: 42)
            print("Number flag: \(numberFlag.asNumber())")

            let allFlags = try await sdk.flags().all()
            print("Fetched \(allFlags.count) flags")
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}