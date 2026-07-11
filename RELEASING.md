# Releasing

## Checklist

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Move relevant entries from `Unreleased` to a dated version in `CHANGELOG.md`.
3. Run a clean Release build and all tests.
4. Archive with a Developer ID Application certificate and Hardened Runtime enabled.
5. Submit the archive or packaged app to Apple's notary service.
6. Staple the notarization ticket and verify the final artifact with both `codesign` and `spctl`.
7. Create a signed Git tag matching the version, for example `v1.0.0`.
8. Create a GitHub Release and attach the notarized artifact plus checksums.

## Local verification

```sh
codesign --verify --deep --strict --verbose=2 CodexLimitBar.app
spctl --assess --type execute --verbose=2 CodexLimitBar.app
shasum -a 256 CodexLimitBar.zip
```

Signing identities, Apple account credentials, App Store Connect API keys, and notary profiles must remain outside the repository and GitHub Actions logs.
