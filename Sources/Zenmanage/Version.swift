/// Identifies this release of the SDK.
public enum ZenmanageSDK {
    /// The SDK's semantic version. It is sent to the API as part of the
    /// `X-ZEN-CLIENT-AGENT` header (`zenmanage-swift/<version>`).
    ///
    /// Keep it in step with the released section of `CHANGELOG.md` when you cut a release;
    /// `ReleaseVersionTests` fails if they drift.
    public static let version = "1.0.0"
}
