# Security Policy

## Supported versions

Security fixes are applied to the latest release.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature instead of a public issue. Include reproduction steps and impact, but do not include Codex credentials, session content, or private source code.

## Data access

Codex Limit Bar reads recent JSONL tails from `~/.codex/sessions` and `~/.codex/archived_sessions`. It does not use the network, read authentication files, or access the macOS Keychain.

