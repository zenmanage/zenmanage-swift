# Contributing

Thanks for your interest in contributing.

## Development Setup

1. Install Xcode 15+ (Swift 5.9+)
2. Clone the repository
3. Run the tests

~~~bash
swift test --enable-code-coverage
~~~

4. Check that the package still builds for iOS

~~~bash
xcodebuild -scheme ZenmanageSwift -destination 'generic/platform=iOS' build
~~~

`swift test` runs on macOS, so this is the check that catches anything that only breaks
on the iOS SDK.

## Quality Bar

- Keep public APIs documented
- Add tests for all behavior changes; CI fails below 90% line coverage
- Preserve backward compatibility unless explicitly changing major versions
- Keep the Objective-C bridge (`ObjectiveC.swift`) in step with the Swift API
- Keep examples and README aligned with actual API behavior

## Versioning

The SDK version lives in `Sources/Zenmanage/Version.swift` (it is sent to the API in the client-agent header) and in a dated `## [X.Y.Z]` section of `CHANGELOG.md`. A test fails if they disagree.

## Pull Requests

- Keep PRs focused and reviewable
- Include rationale in commit messages and PR description
- Update CHANGELOG.md for user-visible changes
