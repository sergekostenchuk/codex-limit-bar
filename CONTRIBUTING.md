# Contributing

Thank you for helping improve Codex Limit Bar.

## Development workflow

1. Fork the repository and create a focused branch.
2. Keep changes small and avoid unrelated formatting rewrites.
3. Add or update tests when changing event parsing or limit calculations.
4. Run the build and test commands from the README.
5. Open a pull request that explains the user-visible behavior and verification performed.

## Code guidelines

- Keep the application native and dependency-free.
- Preserve the low-overhead polling design.
- Do not add credential, cookie, Keychain, or authentication-token access.
- Do not add network transmission without an explicit privacy discussion.
- Treat the local Codex JSONL schema as versionable and potentially absent.

## Reporting bugs

Include the macOS version, Codex version, expected behavior, and observed behavior. Redact session content and never attach authentication files.

