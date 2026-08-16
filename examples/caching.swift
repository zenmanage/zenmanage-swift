import Foundation
import Zenmanage

@main
enum CachingExample {
    static func main() async {
        do {
            let token = ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here"

            let persistentSDK = try Zenmanage(
                environmentToken: token,
                cache: UserDefaultsRuleCache(namespace: "examples.persistent")
            )

            let memorySDK = try Zenmanage(
                environmentToken: token,
                cache: InMemoryRuleCache()
            )

            let noCacheSDK = try Zenmanage(
                environmentToken: token,
                cache: NullRuleCache()
            )

            _ = try await persistentSDK.flags().single("example-flag", defaultValue: false)
            _ = try await memorySDK.flags().single("example-flag", defaultValue: false)
            _ = try await noCacheSDK.flags().single("example-flag", defaultValue: false)

            try await persistentSDK.flags().refreshRules()
            print("Caching examples completed")
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}