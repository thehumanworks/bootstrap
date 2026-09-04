# Repository instructions

Architecture decisions live in [`docs/adrs/`](docs/adrs/). Read those ADRs
before changing bootstrap, secrets, tool wrapping, or sandbox shell setup.

## Live Modal integration testing

After making any change in this repository, always run the relevant end-to-end integration test against the user's live Modal account.

- Treat the live Modal test as a required completion gate, not an optional follow-up.
- Use the least-destructive test that proves the changed behavior and clean up resources created by the test.
- Never print, log, or persist Modal credentials or injected secret values.
- If the live test cannot be run or does not pass, report the change as unverified and state the exact blocker; do not describe the work as complete.
