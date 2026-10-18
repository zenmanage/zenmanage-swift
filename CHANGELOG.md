# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-18

First public release.

### Added
- Native async/await API for fetching and evaluating flags: `Zenmanage`, `FlagManager` (`single`, `all`, `withContext`, `withDefaults`, `reportUsage`, `refreshRules`), `Context`, `Attribute`, and `DefaultsCollection`.
- Local rule evaluation after a single rules fetch. Rules are evaluated from the lowest `position` to the highest and the first match wins; rules that share a position, or have none, keep the payload order.
- Deterministic percentage rollouts using CRC32B bucketing.
- `boolean`, `string`, `number` and `json` flags. `Flag.asJson()` returns the decoded value as a `JSONValue` (`.object`/`.array`/`.string`/`.number`/`.boolean`/`.null`), which conforms to the `ExpressibleBy...` literal protocols so Swift dictionary and array literals work directly. A Dictionary or Array default passed to `single(key, defaultValue:)` or `DefaultsCollection.set(_:json:)` produces a `json`-typed flag. Calling the "wrong" accessor never throws; each accessor falls back to a safe zero value, matching the cross-SDK coercion contract.
- A flag with a `type` this release doesn't recognize no longer fails the whole rules payload. It is logged once and treated like a missing flag, falling back to your default.
- `single()` falls back to the default you provided (or a `DefaultsCollection` entry) instead of throwing when the rules can't be loaded, e.g. an invalid key or no network. An explicit `refreshRules()` still surfaces its own failure.
- Environment tokens must be a mobile key (`mob_...`) or a client key (`cli_...`). Server keys (`srv_...`) are rejected when the configuration is created: a server key bundled into an app can be extracted by anyone.
- `UserDefaults`, in-memory, and null rule caches.
- `ZenmanageConfiguration(requestTimeout:)` (and the matching `Zenmanage(environmentToken:requestTimeout:)` parameter) sets how long a request may wait for data before it fails. It defaults to 10 seconds, the same as the other Zenmanage SDKs; usage reports are capped at 5 seconds.
- `ZenmanageSDK.version`, the version reported to the API in the `X-ZEN-CLIENT-AGENT` header.
- Objective-C bridge types for mixed-language apps, including JSON defaults (`setJson:forKey:` and `NSDictionary`/`NSArray` defaults) and `reportUsage:context:`.
- Swift Package Manager and CocoaPods package definitions, documentation, and examples (including `examples/json-flags.swift`).
