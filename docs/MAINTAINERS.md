# Maintainer guide

These instructions are for people (and agents) changing this repository
itself. They deliberately do NOT live in `AGENTS.md`: `mise bootstrap
--from` clones the whole repo onto every sandbox host, and agent
harnesses auto-load `AGENTS.md` from any directory they work in — so a
maintainer-only test gate would be injected into sandbox agents where it
is meaningless. Keep this file out of harness-magic filenames.

Architecture decisions live in [`adrs/`](adrs/). Read those ADRs before
changing bootstrap, secrets, tool wrapping, or sandbox shell setup.

## Contract tests

Run `mise run test` (or `python -m unittest discover -s tests`) after
any config change. These are static assertions on `mise.toml`; they do
not prove runtime behavior.

## Live Modal integration testing

After making any change in this repository, always run the relevant
end-to-end integration test against the user's live Modal account. The
`sb` harness lives in the separate sandboxes repository, not this
checkout.

- Treat the live Modal test as a required completion gate, not an optional follow-up.
- Use the least-destructive test that proves the changed behavior and clean up resources created by the test.
- Never print, log, or persist Modal credentials or injected secret values.
- If the live test cannot be run or does not pass, report the change as unverified and state the exact blocker; do not describe the work as complete.
