import Foundation
import Zenmanage

@main
enum JSONFlagsExample {
    static func main() async {
        do {
            let sdk = try Zenmanage(environmentToken: ProcessInfo.processInfo.environment["ZENMANAGE_ENVIRONMENT_TOKEN"] ?? "mob_your_mobile_key_here")

            // A Dictionary or Array default becomes a json-typed flag, so it comes back
            // through asJson() unchanged when the flag is missing or can't be loaded.
            let flag = try await sdk.flags().single("theme-config", defaultValue: ["mode": "light", "accent": "blue"])

            // asJson() returns a JSONValue: .object, .array, .string, .number, .boolean or .null.
            // Calling it on a flag that isn't json-typed returns an empty object, never an error.
            if case let .object(theme) = flag.asJson() {
                if case let .string(mode)? = theme["mode"] {
                    print("mode: \(mode)")
                }
                if case let .string(accent)? = theme["accent"] {
                    print("accent: \(accent)")
                }
            }

            // Array-valued flags work the same way.
            let regions = try await sdk.flags().single("allowed-regions", defaultValue: ["us", "ca"])
            if case let .array(items) = regions.asJson() {
                let codes = items.compactMap { item -> String? in
                    if case let .string(code) = item { return code }
                    return nil
                }
                print("allowed regions: \(codes.joined(separator: ", "))")
            }

            // Targeting works the same as for every other flag type.
            let context = Context(type: "user", identifier: "user-123", attributes: [Attribute("country", values: ["US"])])
            let personalised = try await sdk.flags().withContext(context).single("theme-config", defaultValue: ["mode": "light"])
            print("personalised theme: \(personalised.asJson())")
        } catch {
            print("Example failed: \(error.localizedDescription)")
        }
    }
}
