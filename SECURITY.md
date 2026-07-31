# Security Policy

## Supported versions

Security fixes are applied to the latest release.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature instead of a public issue. Include reproduction steps and impact, but do not include Codex credentials, session content, or private source code.

## Data access

Codex Limit Bar reads recent JSONL tails from `~/.codex/sessions` and `~/.codex/archived_sessions`. It does not read authentication files or access the macOS Keychain.

When Reset Radar is enabled, the app makes an unauthenticated GET request to the public `status.openai.com/api/v2/incidents.json` endpoint every 15 minutes. No local usage data, account data, credentials, or cookies are included. Reset Radar can be disabled from the app menu to stop all network requests.
