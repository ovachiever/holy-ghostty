# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in Holy Ghostty, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email the maintainer directly or use GitHub's private vulnerability reporting feature on the repository's Security tab.

Include:

- A description of the vulnerability
- Steps to reproduce
- The potential impact
- Any suggested fixes, if you have them

You should receive a response within 48 hours.

## Scope

Security concerns for this project include:

- **Session data**: Holy Ghostty persists session records, launch specs, environment variables, and archive data under `~/Library/Application Support/`. Leaks or improper handling of session state are in scope.
- **Worktree management**: managed worktrees are created and owned by the app. Path traversal or unintended file access through worktree operations is in scope.
- **Terminal surface**: the terminal core is upstream Ghostty. Terminal-level vulnerabilities (escape sequence injection, etc.) should be reported to the [upstream Ghostty project](https://github.com/ghostty-org/ghostty).
- **Credential exposure**: environment variables passed to sessions may contain secrets. Improper logging or persistence of those values is in scope.

## Out of Scope

- Vulnerabilities in upstream Ghostty's terminal core (report those upstream)
- Issues requiring physical access to the machine
- Social engineering

## Supported Versions

Security fixes are applied to the latest release only.
