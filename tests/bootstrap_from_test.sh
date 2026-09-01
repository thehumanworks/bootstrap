#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_dir="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"
repo_root="$(cd -- "$test_dir/.." && pwd -P)"
mise_bin="${MISE_BIN:-$(type -P mise 2>/dev/null || true)}"
[[ -x "$mise_bin" ]] || fail "mise is required for the --from smoke test"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
source_repo="$tmp/source"
mkdir -p "$source_repo" "$tmp/empty"

git init -q -b main "$source_repo"
git -C "$repo_root" archive HEAD | tar -x -C "$source_repo"
git -C "$source_repo" add -A
git -C "$source_repo" \
  -c user.name=Bootstrap-Test \
  -c user.email=bootstrap-test@example.invalid \
  commit -q -m fixture

for profile in dev work; do
  home="$tmp/home-$profile"
  checkout="$tmp/checkout-$profile"
  data="$tmp/data-$profile"
  cache="$tmp/cache-$profile"
  state="$tmp/state-$profile"
  mkdir -p "$home"

  for _pass in 1 2; do
    (
      cd "$tmp/empty"
      HOME="$home" \
        MISE_DATA_DIR="$data" \
        MISE_CACHE_DIR="$cache" \
        MISE_STATE_DIR="$state" \
        OP_SERVICE_ACCOUNT_TOKEN=test-placeholder-not-a-secret \
        "$mise_bin" -E "$profile" bootstrap \
        --from "$source_repo" \
        --from-dir "$checkout" \
        --yes \
        --only dotfiles,mise-shell-activate
    )
  done

  [[ -L "$home/.config/mise/config.toml" ]] ||
    fail "$profile did not install the global mise config link"
  [[ "$(readlink -f "$home/.config/mise/config.toml")" == "$checkout/mise/conf.d/tools.toml" ]] ||
    fail "$profile global mise link points at the wrong checkout"

  [[ -f "$home/.config/fnox/config.toml" &&
    ! -L "$home/.config/fnox/config.toml" ]] ||
    fail "$profile fnox config was not copied"
  [[ -f "$home/.config/git/config" ]] ||
    fail "$profile Git config is missing"
  [[ -f "$home/.claude/settings.json" ]] ||
    fail "$profile Claude settings are missing"
  [[ -f "$home/.codex/config.toml" ]] ||
    fail "$profile Codex settings are missing"
  [[ ! -e "$home/.claude.json" ]] ||
    fail "$profile unexpectedly manages mutable Claude state"

  case "$profile" in
  dev)
    cmp -s "$home/.config/fnox/config.toml" "$checkout/fnox.toml" ||
      fail "dev selected the wrong fnox config"
    ;;
  work)
    cmp -s "$home/.config/fnox/config.toml" "$checkout/fnox.work.toml" ||
      fail "work selected the wrong fnox config"
    ;;
  esac

  [[ -z "$(git -C "$checkout" status --porcelain)" ]] ||
    fail "$profile bootstrap dirtied its checkout"
done

printf 'bootstrap --from smoke tests passed\n'
