# Releasing

The SDK is distributed through Swift Package Manager (straight from the git tag) and CocoaPods Trunk. There is no automated publish workflow; a release is a PR, a tag, and a `pod trunk push`.

## Where the version lives

The version appears in three places, and they must match. `ReleaseVersionTests` fails CI if they drift.

| Where | What |
|---|---|
| `Sources/Zenmanage/Version.swift` | `ZenmanageSDK.version`, sent to the API as `X-ZEN-CLIENT-AGENT: zenmanage-swift/<version>` |
| `Zenmanage.podspec` | `spec.version` |
| `CHANGELOG.md` | a dated `## [X.Y.Z] - YYYY-MM-DD` section |

Also update the install examples in `README.md` when the major version changes.

## Release steps

1. **Prepare the release PR.** Bump the version in the three places above, move the `## [Unreleased]` entries under the new heading, and set its date. Platform minimums (`iOS 13`, `macOS 10.15`, `tvOS 13`, `watchOS 6`) live in both `Package.swift` and the podspec; keep them in sync.
2. **Run the quality gates** locally before merging:

   ```bash
   swift test --enable-code-coverage
   xcodebuild -scheme ZenmanageSwift -destination 'generic/platform=iOS' build
   pod lib lint Zenmanage.podspec --allow-warnings
   ```

   If CocoaPods isn't installed: `sudo gem install cocoapods`. Also run the shared integration parity suite (`sdks/debuggers/sdk-integration-tests/feature-parity-swift`) when evaluation behavior changed.
3. **Merge to `main`**, then tag the merge commit. Swift Package Manager and CocoaPods both use a plain version tag with no `v` prefix:

   ```bash
   git tag -a X.Y.Z -m "Release X.Y.Z"
   git push origin X.Y.Z
   ```

   Swift Package Manager needs nothing more; the tag is the release. Never move or delete a published tag.
4. **Publish to CocoaPods Trunk.** The tag must already be pushed:

   ```bash
   pod spec lint Zenmanage.podspec --allow-warnings
   pod trunk push Zenmanage.podspec --allow-warnings
   ```

   Trunk sessions expire; re-authenticate with `pod trunk register <email> 'Zenmanage' --description='Zenmanage SDK maintainer'` if the push is rejected.

   **CocoaPods Trunk is scheduled to become read-only on 2 December 2026**, after which no new pods or versions can be published. Existing pods keep working, and apps can still use the package by git tag.
5. **Create a GitHub Release** from the tag with the changelog entries as the body.
6. **Verify** from a fresh iOS project: add `https://github.com/zenmanage/zenmanage-swift` at the new version (Swift Package Manager), and `pod 'Zenmanage', '~> X.Y'` followed by `pod install` (CocoaPods). Both must resolve and build.

## One-time setup

- **Repository:** public, with a description, homepage, and topics (`feature-flags`, `feature-toggles`, `feature-management`, `remote-config`, `zenmanage`, `ios`, `swift`).
- **Branch protection on `main`:** require pull requests and the `test` and `ios` status checks from `.github/workflows/ci.yml`.
- **CocoaPods Trunk:** register a maintainer session with `pod trunk register` and check it with `pod trunk me`.
- **Swift Package Index:** after the repository is public, submit it at <https://swiftpackageindex.com/add-a-package>. It is a discovery surface, not a host.
- **Objective-C:** before announcing, install the package in an Objective-C app, `@import Zenmanage;`, initialize `ZMObjCZenmanage`, and fetch a flag through the completion handler.
