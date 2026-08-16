import Foundation
import Zenmanage

@main
enum DefaultsExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            let defaults = DefaultsCollection()
                .set("feature-new-ui", bool: true)
                .set("api-version", string: "v2")
                .set("max-items-per-page", int: 50)
                .set("enable-analytics", bool: false)

            let flagManager = sdk.flags().withDefaults(defaults)

            let uiFlag = try await flagManager.single("feature-new-ui")
            let apiFlag = try await flagManager.single("api-version")
            let itemsFlag = try await flagManager.single("max-items-per-page")

            print("feature-new-ui: \(uiFlag.isEnabled())")
            print("api-version: \(apiFlag.asString())")
            print("max-items-per-page: \(itemsFlag.asNumber())")
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}