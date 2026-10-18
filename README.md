# Zenmanage Swift SDK

[![Platform](https://img.shields.io/badge/platform-iOS%2013%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Add Zenmanage feature flags to iOS apps with a native Swift package that mirrors the local-evaluation model used by the Zenmanage PHP and JavaScript SDKs.

## Features

- Native Swift implementation for iOS and Apple platform apps
- Local rule evaluation after a single rules fetch
- Percentage rollouts with deterministic CRC32B bucketing
- `UserDefaults` cache by default, plus in-memory and null cache options
- Async/await-friendly public API
- Objective-C bridge for mixed-language apps
- CocoaPods and Swift Package Manager support
- Inline documentation, runnable examples, and a tested public API surface

## Requirements

- iOS 13+
- Xcode 15+
- Swift 5.9+

## Key Compatibility

This SDK is for mobile runtimes and is meant to be used with environment tokens prefixed with `mob_`.

- `mob_...`: supported
- `cli_...`: rejected when the configuration is created
- `srv_...`: accepted by the client, but the Zenmanage API rejects server keys for this SDK's client agent

## Installation

### Swift Package Manager

Add the package in Xcode or `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/zenmanage/zenmanage-swift.git", from: "0.1.0")
]
```

Then depend on the `Zenmanage` product.

### CocoaPods

```ruby
pod 'Zenmanage', '~> 0.1'
```

## Quick Start

```swift
import Zenmanage

let sdk = try Zenmanage(environmentToken: "mob_your_mobile_key_here")

let flag = try await sdk.flags().single("new-dashboard", defaultValue: false)

if flag.isEnabled() {
    showNewDashboard()
} else {
    showOldDashboard()
}
```

## Configuration

```swift
import Zenmanage

let configuration = try ZenmanageConfiguration(
    environmentToken: "mob_your_mobile_key_here",
    cacheTTL: 3600,
    cache: UserDefaultsRuleCache(),
    enableUsageReporting: true,
    requestTimeout: 10
)

let sdk = Zenmanage(configuration: configuration)
```

`requestTimeout` is how long, in seconds, a request may wait for data before it fails (default `10`, the same as the other Zenmanage SDKs). Usage reports are capped at 5 seconds. A rules fetch makes up to three attempts, each with two requests (the rules location, then the rules file), after which `single()` falls back to your default value. In the worst case of a network that never answers that is about a minute at the default; lower `requestTimeout` if you'd rather give up sooner. Pass your own `urlSession` if you need proxy or certificate-pinning behavior.

### Cache Options

```swift
let persistent = try Zenmanage(
    environmentToken: "mob_your_mobile_key_here",
    cache: UserDefaultsRuleCache()
)

let ephemeral = try Zenmanage(
    environmentToken: "mob_your_mobile_key_here",
    cache: InMemoryRuleCache()
)

let uncached = try Zenmanage(
    environmentToken: "mob_your_mobile_key_here",
    cache: NullRuleCache()
)
```

## Context-Based Evaluation

```swift
import Zenmanage

let context = Context(
    type: "user",
    name: "Taylor",
    identifier: "user-123",
    attributes: [
        Attribute("country", values: ["US"]),
        Attribute("plan", values: ["pro"]),
    ]
)

let flag = try await sdk.flags()
    .withContext(context)
    .single("premium-dashboard", defaultValue: false)
```

Rules are evaluated from the lowest `position` to the highest and the first match wins, whatever order they arrive in.

## Percentage Rollouts

```swift
let context = Context.single(type: "user", identifier: "user-123")
let flag = try await sdk.flags()
    .withContext(context)
    .single("new-checkout-flow", defaultValue: false)

if flag.isEnabled() {
    renderNewFlow()
}
```

The SDK hashes `salt:contextIdentifier` with CRC32B and assigns the context to a stable bucket from `0` to `99`. Increasing the rollout percentage only adds new users; it never flips an already-included user out of the rollout.

## Default Values

```swift
let defaults = DefaultsCollection()
    .set("new-ui", bool: true)
    .set("checkout-variant", string: "control")
    .set("page-size", int: 20)
    .set("advanced-config", json: ["retries": 3, "timeout-ms": 5000])

let manager = sdk.flags().withDefaults(defaults)
let pageSize = try await manager.single("page-size").asNumber()

// A Dictionary or Array default (or an explicit `JSONValue`) synthesizes a `json`-typed
// flag rather than being coerced to a string.
let config = try await manager.single("advanced-config", defaultValue: ["retries": 3]).asJson()
```

## Value Types & Cross-Type Coercion

A flag's `type` is one of `boolean`, `string`, `number`, or `json`. Each type has a matching accessor (`asBool()`, `asString()`, `asNumber()`, `asJson()`), plus `isEnabled()` for boolean flags specifically. This is the reference other Zenmanage SDKs mirror, so the rules below are intentionally exact — not just "reasonable defaults."

**`asJson()`** returns the decoded value as a `JSONValue`, this SDK's minimal representation of an arbitrary JSON value (`.object([String: JSONValue])`, `.array([JSONValue])`, `.string`, `.number`, `.boolean`, `.null`). Both JSON objects (`{"a": 1}`) and JSON arrays (`[1, 2, 3]`) decode to their matching `JSONValue` case. `JSONValue` also conforms to `ExpressibleByDictionaryLiteral`/`ExpressibleByArrayLiteral`/`ExpressibleByStringLiteral`/etc., so Swift dictionary and array literals (like the `advanced-config` example above) can be passed anywhere a `JSONValue` is expected without spelling out the enum case.

**Calling the "wrong" accessor for a flag's type never throws.** Each accessor only recognizes its own value wrapper (`{"boolean": …}`, `{"string": …}`, `{"number": …}`, `{"json": …}`) and falls back to a safe zero value for every other type — it never attempts a lossy conversion between types:

| Called on →<br>Flag type ↓ | `asBool()` | `asString()` | `asNumber()` | `asJson()` |
|---|---|---|---|---|
| `boolean` | the bool | `""` | `0` | `.empty` (`.object([:])`) |
| `string` | `true` | the string | `0` | `.empty` |
| `number` | `true` | `""` | the number | `.empty` |
| `json` | `true` | `""` | `0` | the decoded value |

**`asBool()` on a `json` flag returns `true` unconditionally**, the same as every other non-boolean type — it doesn't inspect the decoded value. Use `isEnabled()`, not `asBool()`, when you specifically mean "is this boolean flag on" — `isEnabled()` returns `false` outright for any non-boolean flag instead. A `json` flag whose decoded value isn't itself an object or array (a bare JSON scalar such as `5` or `"x"`, which the API allows but which real flags won't normally use) makes `asJson()` return `.empty` too — the same safe-zero-value behavior as calling it on a non-json flag, rather than wrapping the scalar or throwing.

**Default values** passed to `single(key, defaultValue:)` or `DefaultsCollection` are typed from the Swift value itself: a Dictionary or Array default becomes a `json`-typed flag (not a stringified fallback), so `asJson()` on a missing flag with a Dictionary/Array default returns that value unchanged.

## Objective-C Support

The package includes Objective-C bridge classes for apps that still use Objective-C UI or shared layers.

```objective-c
@import Zenmanage;

ZMObjCZenmanage *sdk = [[ZMObjCZenmanage alloc] initWithEnvironmentToken:@"mob_your_mobile_key_here"
                                                                cacheTTL:@3600
                                                   enableUsageReporting:YES
                                                             apiEndpoint:@"https://api.zenmanage.com"
                                                                   error:nil];
```

```objective-c
ZMObjCContext *context = [[ZMObjCContext alloc] initWithType:@"user"
                                                        name:nil
                                                  identifier:@"user-123"
                                                  attributes:@[
    [[ZMObjCAttribute alloc] initWithKey:@"country" values:@[@"US"]]
]];

// Defaults can be a string, a number, a boolean, or an NSDictionary / NSArray for a json flag.
[[sdk flags] single:@"advanced-config"
       defaultValue:@{ @"retries": @3 }
            context:context
         completion:^(ZMObjCFlag *flag, NSError *error) {
    if (flag != nil) {
        NSDictionary *config = [flag asJson];
        NSLog(@"retries: %@", config[@"retries"]);
    }
}];

ZMObjCDefaultsCollection *defaults = [[ZMObjCDefaultsCollection alloc] init];
[[defaults setBool:YES forKey:@"new-ui"] setJson:@[@"us", @"ca"] forKey:@"allowed-regions"];

[[sdk flags] reportUsage:@"new-ui" context:context];
```

Primary bridge types:

- `ZMObjCZenmanage`
- `ZMObjCFlagManager`
- `ZMObjCContext`
- `ZMObjCAttribute`
- `ZMObjCDefaultsCollection`
- `ZMObjCFlag`

`NSDictionary` and `NSArray` defaults (and `setJson:forKey:`) hold strings, numbers, booleans, `NSNull`, and nested dictionaries and arrays; anything else inside them is stored as `null`.

## Examples

The package includes the same example set used by the other Zenmanage SDKs, adapted for Swift:

- [examples/simple-flags.swift](examples/simple-flags.swift)
- [examples/ab-testing.swift](examples/ab-testing.swift)
- [examples/caching.swift](examples/caching.swift)
- [examples/context-based-flags.swift](examples/context-based-flags.swift)
- [examples/defaults.swift](examples/defaults.swift)
- [examples/json-flags.swift](examples/json-flags.swift)
- [examples/percentage-rollouts.swift](examples/percentage-rollouts.swift)

## Testing

Run the package tests with coverage enabled:

```bash
swift test --enable-code-coverage
```

CI fails below 90% line coverage and also builds the package for iOS, which `swift test` (macOS) can't catch:

```bash
xcodebuild -scheme ZenmanageSwift -destination 'generic/platform=iOS' build
```

The suite covers configuration validation and request timeouts, the `UserDefaults`, in-memory and null caches (including a cache that can't be read or written), rule evaluation against the payload shape the API serves, rule ordering by `position`, rollout bucketing, rule fetching, default handling, json flag decoding and coercion, tolerating unrecognized flag types, and the Objective-C bridge.

Like every other Zenmanage SDK, this one also runs the shared integration parity suite against a real environment; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Publishing

See [docs/PUBLISHING.md](docs/PUBLISHING.md) for the release checklist covering GitHub, CocoaPods, Swift Package Manager distribution, and Swift Package Index registration.