# Releasing

The SDK is distributed through Swift Package Manager, straight from the git tag. There is no automated publish workflow and no package registry account; a release is a PR, a tag, and a GitHub Release.

## Where the version lives

The version appears in two places, and they must match. `ReleaseVersionTests` fails CI if they drift.

| Where | What |
|---|---|
| `Sources/Zenmanage/Version.swift` | `ZenmanageSDK.version`, sent to the API as `X-ZEN-CLIENT-AGENT: zenmanage-swift/<version>` |
| `CHANGELOG.md` | a dated `## [X.Y.Z] - YYYY-MM-DD` section |

Also update the install example in `README.md` when the major version changes.

## Release steps

1. **Prepare the release PR.** Bump the version in the two places above, move the `## [Unreleased]` entries under the new heading, and set its date. Platform minimums (`iOS 13`, `macOS 10.15`, `tvOS 13`, `watchOS 6`) live in `Package.swift`.
2. **Run the quality gates** locally before merging:

   ```bash
   swift test --enable-code-coverage
   xcodebuild -scheme ZenmanageSwift -destination 'generic/platform=iOS' build
   ```

   Also run the shared integration parity suite (`sdks/debuggers/sdk-integration-tests/feature-parity-swift`) when evaluation behavior changed.
3. **Merge to `main`**, then tag the merge commit with a plain version tag (no `v` prefix):

   ```bash
   git tag -a X.Y.Z -m "Release X.Y.Z"
   git push origin X.Y.Z
   ```

   Swift Package Manager needs nothing more; the tag is the release. Never move or delete a published tag.
4. **Create a GitHub Release** from the tag with the changelog entries as the body.
5. **Verify** from a fresh iOS project: add `https://github.com/zenmanage/zenmanage-swift` at the new version. It must resolve and build.

## One-time setup

- **Repository:** public, with a description, homepage, and topics (`feature-flags`, `feature-toggles`, `feature-management`, `remote-config`, `zenmanage`, `ios`, `swift`).
- **Branch protection on `main`:** require pull requests and the `test` and `ios` status checks from `.github/workflows/ci.yml`.
- **Swift Package Index:** after the repository is public, submit it at <https://swiftpackageindex.com/add-a-package>. It is a discovery surface, not a host.
- **Objective-C:** before announcing, install the package in an Objective-C app, `@import Zenmanage;`, initialize `ZMObjCZenmanage`, and fetch a flag through the completion handler.

## CocoaPods

The SDK is distributed through Swift Package Manager only and is not published to CocoaPods, so the repository doesn't carry a podspec.
