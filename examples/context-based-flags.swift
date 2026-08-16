import Foundation
import Zenmanage

@main
enum ContextBasedFlagsExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            let context = Context(
                type: "user",
                name: "Sam",
                identifier: "user-98765",
                attributes: [
                    Attribute("subscription_plan", values: ["premium", "annual"]),
                    Attribute("country", values: ["US"]),
                    Attribute("signup_date", values: ["2024-01-15"]),
                ]
            )

            let flag = try await sdk.flags()
                .withContext(context)
                .single("premium-feature", defaultValue: false)

            print("Premium feature enabled: \(flag.isEnabled())")
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}