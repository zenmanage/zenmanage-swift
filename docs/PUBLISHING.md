# Publishing Next Steps

This document covers the remaining work needed to publish the Swift SDK to the public package ecosystems.

## 1. Finalize Repository Metadata

- Move the contents of `zenmanage-swift/` into the dedicated public repository root if this folder will become its own repo.
- Confirm the public repository URL and update these files if the final location changes:
  - `README.md`
  - `Zenmanage.podspec`
  - `.github/workflows/ci.yml`
- Add issue tracker, repository topics, and a short repository description on GitHub.

## 2. Validate Release Artifacts Locally

Run these commands before tagging a release:

```bash
swift test --enable-code-coverage
swift package dump-package
pod lib lint Zenmanage.podspec --allow-warnings
```

If CocoaPods is not installed yet:

```bash
sudo gem install cocoapods
```

## 3. Create The First Public Release

1. Set the package version consistently in:
   - `CHANGELOG.md`
   - `Zenmanage.podspec`
   - Git tag name
2. Commit the release changes.
3. Create an annotated tag:

```bash
git tag -a 0.1.0 -m "Release 0.1.0"
git push origin main --tags
```

4. Create a GitHub release from that tag and paste the changelog notes.

## 4. Publish For Swift Package Manager Consumers

Swift Package Manager distribution is already enabled by `Package.swift`.

To make it consumable publicly:

- Ensure the public GitHub repository is reachable without authentication.
- Keep semver tags in place.
- Test install from a fresh sample app using:

```swift
.package(url: "https://github.com/zenmanage/zenmanage-swift.git", from: "0.1.0")
```

Optional next steps:

- Register the package with a private or public Swift package registry if you plan to distribute through registries in addition to Git tags.
- Add DocC generation or hosted API docs if you want richer package documentation in Xcode.

## 5. Publish To CocoaPods

One-time setup:

```bash
pod trunk register you@example.com 'Your Name' --description='Zenmanage Swift SDK publishing'
```

Publish the tagged release:

```bash
pod trunk push Zenmanage.podspec
```

Recommended checks:

- Run `pod spec lint Zenmanage.podspec --allow-warnings` in CI.
- Confirm the Git tag in `spec.source` matches the release tag exactly.
- Verify the pod appears on https://cocoapods.org after trunk propagation.

## 6. Register With Swift Package Index

Swift Package Index is not a package host, but it is the main public discovery surface for Swift packages.

After the repository is public:

1. Open https://swiftpackageindex.com/add-a-package
2. Submit the GitHub repository URL
3. Enable build and documentation compatibility reporting if available

This improves discoverability for SwiftPM users and gives you public compatibility badges.

## 7. Add Release Automation

Recommended follow-up automation:

- CI job to run `swift test --enable-code-coverage`
- CI job to run `pod lib lint Zenmanage.podspec --allow-warnings`
- Optional release workflow that creates GitHub releases from version tags
- Optional Dependabot or Renovate configuration for CI upkeep

## 8. Verify Objective-C Consumption

Before the public launch, validate the bridge from a sample Objective-C app:

- Install through SwiftPM or CocoaPods in an Objective-C iOS project
- Import the module and initialize `ZMObjCZenmanage`
- Fetch a flag using completion handlers
- Confirm the generated Objective-C headers expose the bridge types as expected

## 9. Documentation Follow-Ups

Before announcing the package publicly, consider adding:

- A migration guide when the first breaking change happens
- A dedicated troubleshooting section for networking, caching, and key mismatches
- A short architecture note describing local rule evaluation and rollout bucketing
- Screenshots or short snippets showing SwiftUI and UIKit integration