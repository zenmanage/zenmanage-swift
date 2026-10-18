# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `ZenmanageConfiguration(requestTimeout:)` (and the matching `Zenmanage(environmentToken:requestTimeout:)` parameter) sets how long a request may wait for data before it fails. It defaults to 10 seconds, the same as the other Zenmanage SDKs; usage reports are capped at 5 seconds.
- Objective-C bridge: `ZMObjCDefaultsCollection setJson:forKey:`, `NSDictionary` / `NSArray` defaults for `-[ZMObjCFlagManager single:defaultValue:context:completion:]` (json flags), and `-[ZMObjCFlagManager reportUsage:context:]`.
- `examples/json-flags.swift`, `CONTRIBUTING.md`, and a Dependabot config for Swift packages and GitHub Actions.
- CI now builds the package for iOS and fails below 90% line coverage.
- Support for `json`-typed flags: `Flag.asJson()` returns the decoded value as a new `JSONValue` type (`.object`/`.array`/`.string`/`.number`/`.boolean`/`.null`), matching the "own type only, safe fallback otherwise" coercion behavior of `asBool()`/`asString()`/`asNumber()`. `JSONValue` conforms to `ExpressibleByDictionaryLiteral`/`ExpressibleByArrayLiteral`/etc. so Swift dictionary and array literals can be used directly. A Dictionary or Array default passed to `single(key, defaultValue:)` or `DefaultsCollection.set(_:json:)` now synthesizes a `json`-typed flag instead of being coerced to a string.

### Fixed
- Rules are now evaluated from the lowest `position` to the highest (rules sharing a position, or without one, keep the payload order), matching the PHP, Ruby, and Flutter SDKs. Previously they were evaluated in payload order, which isn't guaranteed to be `position` order.
- `Flag.asString()` on a number flag no longer crashes when the value is too large for an `Int` (or is infinite).
- `FlagManager.single()` now falls back to the caller-provided default (or a `DefaultsCollection` entry) instead of throwing when the rules fetch fails outright, e.g. an invalid or unreachable environment token. This mirrors the reference PHP SDK's behavior. An explicit `refreshRules()` call still surfaces its own failure.
- Flags with an unrecognized `type` (or an unrecognized value wrapper) no longer fail to decode. Previously, one flag of an unrecognized type could throw away the entire rules payload; now that flag is treated as unknown, logged once, and evaluates to the caller's default like a missing flag. This shipped ahead of `json`-type flag support above.

### Changed
- Environment tokens must now be a mobile key (`mob_...`) or a client key (`cli_...`), matching the React Native SDK. Server keys (`srv_...`) are rejected when the configuration is created: a server key bundled into an app can be extracted by anyone. Client keys, previously rejected, are now accepted.
- Requests now time out after 10 seconds (5 for usage reports) instead of waiting out `URLSession`'s 60 second default on each of the three attempts. Set `requestTimeout` to change it.
- Renamed request headers to use a consistent `X-ZEN-` prefix: `X-API-Key` → `X-ZEN-API-KEY`, `X-ZENMANAGE-CONTEXT` → `X-ZEN-CONTEXT`, and `X-DEFAULT-VALUE` → `X-ZEN-DEFAULT-VALUE`.

## [0.1.0] - 2026-05-08

### Added
- Initial public Swift SDK for Zenmanage mobile clients
- Native async/await API for fetching and evaluating flags
- Local rule evaluation matching the PHP and JavaScript SDK behavior
- Deterministic percentage rollout support using CRC32B bucketing
- `UserDefaults`, in-memory, and null cache backends
- Objective-C bridge types for mixed-language iOS apps
- Swift Package Manager and CocoaPods package definitions
- Documentation, examples, CI workflow, and publishing guide
- Test coverage for configuration, cache behavior, API fetching, usage reporting, rules, and rollouts