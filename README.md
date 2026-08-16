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

This SDK is for mobile runtimes and requires environment tokens prefixed with `mob_`.

- `mob_...`: supported
- `cli_...`: rejected
- `srv_...`: rejected

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
    enableUsageReporting: true
)

let sdk = Zenmanage(configuration: configuration)
```

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

let manager = sdk.flags().withDefaults(defaults)
let pageSize = try await manager.single("page-size").asNumber()
```

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

Primary bridge types:

- `ZMObjCZenmanage`
- `ZMObjCFlagManager`
- `ZMObjCContext`
- `ZMObjCAttribute`
- `ZMObjCDefaultsCollection`
- `ZMObjCFlag`

## Examples

The package includes the same example set used by the other Zenmanage SDKs, adapted for Swift:

- [examples/simple-flags.swift](examples/simple-flags.swift)
- [examples/ab-testing.swift](examples/ab-testing.swift)
- [examples/caching.swift](examples/caching.swift)
- [examples/context-based-flags.swift](examples/context-based-flags.swift)
- [examples/defaults.swift](examples/defaults.swift)
- [examples/percentage-rollouts.swift](examples/percentage-rollouts.swift)

## Testing

Run the package tests with coverage enabled:

```bash
swift test --enable-code-coverage
```

The included suite covers configuration validation, `UserDefaults` cache behavior, rule evaluation, rollout bucketing, rule fetching, default handling, and Objective-C initialization.

## Publishing

See [docs/PUBLISHING.md](docs/PUBLISHING.md) for the release checklist covering GitHub, CocoaPods, Swift Package Manager distribution, and Swift Package Index registration.