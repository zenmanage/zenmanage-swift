import Foundation
import Zenmanage

@main
enum PercentageRolloutsExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            let users = ["user-1", "user-2", "user-3", "user-4", "user-5"]

            for userID in users {
                let context = Context.single(type: "user", identifier: userID)
                let flag = try await sdk.flags()
                    .withContext(context)
                    .single("new-checkout-flow", defaultValue: false)

                print("\(userID): \(flag.isEnabled() ? "IN rollout" : "NOT in rollout")")
            }
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}