# 0002: Native work profiles and runtime Atlassian authentication

Date: 2026-09-15
Status at creation: accepted

## Context

Modal needs a reusable work image without resolving 1Password during builds.
Mise's selected environment must remain available outside the bootstrap
checkout. Fnox's project hierarchy must not restore personal GitHub credentials.

## Decision

Install native global mise overlays and select work via MISE_ENV. Retain the
work fnox file as the global config, using named work/work-github/work-atlassian
profiles and no-defaults. Work gh and its Git credential helper resolve only
work-github and fail if unavailable; public downloads use MISE_GITHUB_TOKEN.

Install official ACLI and a pinned mcp-remote adapter only in work. Use
Atlassian's official MCP v2 endpoint with runtime Basic auth. Generate Codex's
entry with its CLI; install Claude's work config with mise dotfiles. ACLI uses
stdin login and a temporary credential store per invocation.

## Alternatives and consequences

A renamed GITHUB_TOKEN alone loses to inherited GH_TOKEN. A work global file
alone loses to project fnox defaults. Native named profiles avoid custom
configuration merging. Keeping tokens in the image or client config would
prevent safe rotation. Per-command ACLI login adds latency but leaves no
retained auth store. The MCP adapter adds a pinned dependency to support
runtime-generated Basic headers across both clients.

## Verification

See tests/test_work_profile.py and docs/work-profile.md. The sandboxes
companion contract docs/verification/mise-profiles requires live checks of
both named images, work auth, MCP/CLI reads, and cleanup before completion.
