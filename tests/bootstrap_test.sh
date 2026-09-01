#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_dir="$(
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"
repo_root="$(cd -- "$test_dir/.." && pwd -P)"
bootstrap="$repo_root/bootstrap.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fake_mise="$tmp/mise"
capture="$tmp/args"

cat >"$fake_mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"${MISE_CAPTURE:?}"
exit "${MISE_FAKE_EXIT:-0}"
EOF
chmod +x "$fake_mise"

assert_args() {
  local actual=()
  local expected=("$@")
  local index

  mapfile -d '' -t actual <"$capture"
  ((${#actual[@]} == ${#expected[@]})) ||
    fail "expected ${#expected[@]} arguments, got ${#actual[@]}"

  for ((index = 0; index < ${#expected[@]}; index++)); do
    [[ "${actual[index]}" == "${expected[index]}" ]] ||
      fail "argument $index: expected '${expected[index]}', got '${actual[index]}'"
  done
}

# Invocation is independent of cwd and every bootstrap argument is preserved.
(
  cd "$tmp"
  MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" \
    "$bootstrap" dev --dry-run --skip tools,task \
    --from-dir "$tmp/path with spaces"
)
assert_args \
  -C "$repo_root" \
  -E dev \
  bootstrap \
  --yes \
  --dry-run \
  --skip tools,task \
  --from-dir "$tmp/path with spaces"

# A leading mise option uses the default profile.
MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" "$bootstrap" --dry-run
assert_args -C "$repo_root" -E dev bootstrap --yes --dry-run

# Explicit profile form and the separator both work.
MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" \
  "$bootstrap" --profile=work -- --update --force-dotfiles
assert_args \
  -C "$repo_root" \
  -E work \
  bootstrap \
  --yes \
  --update \
  --force-dotfiles

# Wrapper help does not invoke mise.
rm -f "$capture"
MISE_BIN="$tmp/does-not-exist" "$bootstrap" --help >"$tmp/help"
grep -Fq 'Usage:' "$tmp/help" || fail "wrapper help is missing"
[[ ! -e "$capture" ]] || fail "mise was invoked for wrapper help"

# Invalid and unknown profiles fail before invoking mise.
rm -f "$capture"
if MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" \
  "$bootstrap" ../dev >"$tmp/out" 2>"$tmp/err"; then
  fail "invalid profile unexpectedly succeeded"
fi
grep -Fq "invalid profile '../dev'" "$tmp/err" ||
  fail "invalid-profile error is missing"
[[ ! -e "$capture" ]] || fail "mise was invoked for an invalid profile"

if MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" \
  "$bootstrap" nonexistent >"$tmp/out" 2>"$tmp/err"; then
  fail "unknown profile unexpectedly succeeded"
fi
grep -Fq "unknown profile 'nonexistent'" "$tmp/err" ||
  fail "unknown-profile error is missing"
grep -Fq 'available: dev work' "$tmp/err" ||
  fail "available profiles were not reported"

# mise's exit status is propagated unchanged.
set +e
MISE_BIN="$fake_mise" MISE_CAPTURE="$capture" MISE_FAKE_EXIT=42 \
  "$bootstrap" dev >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 42 ]] || fail "expected mise exit status 42, got $status"

# An invalid explicit binary produces an actionable setup error.
if MISE_BIN="$tmp/missing-mise" \
  "$bootstrap" dev >"$tmp/out" 2>"$tmp/err"; then
  fail "missing mise unexpectedly succeeded"
fi
grep -Fq 'MISE_BIN is not executable' "$tmp/err" ||
  fail "missing-MISE_BIN error is missing"

printf 'bootstrap wrapper tests passed\n'

