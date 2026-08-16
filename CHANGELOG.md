# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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