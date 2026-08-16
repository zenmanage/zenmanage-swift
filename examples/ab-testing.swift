import Foundation
import Zenmanage

@main
enum ABTestingExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            let users = [
                (id: "user-001", name: "Avery", country: "US"),
                (id: "user-002", name: "Jordan", country: "CA"),
                (id: "user-003", name: "Morgan", country: "GB"),
            ]

            for user in users {
                let context = Context(
                    type: "user",
                    name: user.name,
                    identifier: user.id,
                    attributes: [Attribute("country", values: [user.country])]
                )

                let variant = try await sdk.flags()
                    .withContext(context)
                    .single("checkout-flow", defaultValue: "control")

                print("\(user.name) -> \(variant.asString())")
            }
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}