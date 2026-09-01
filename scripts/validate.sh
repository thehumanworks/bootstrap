#!/usr/bin/env bash
set -euo pipefail

script_dir="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
cd "$repo_root"

mapfile -d '' -t shell_files < <(find . -type f -name '*.sh' -print0 | sort -z)

for file in "${shell_files[@]}"; do
  bash -n "$file"
done

if command -v shellcheck >/dev/null; then
  shellcheck "${shell_files[@]}"
fi

if command -v shfmt >/dev/null; then
  shfmt -d "${shell_files[@]}"
fi

python3 - <<'PY'
import json
import pathlib
import tomllib

root = pathlib.Path.cwd()
for path in sorted(root.rglob("*.toml")):
    with path.open("rb") as handle:
        tomllib.load(handle)

for path in sorted(root.rglob("*.json")):
    with path.open(encoding="utf-8") as handle:
        json.load(handle)
PY

for config in .gitconfig .gitconfig.work; do
  git config --file "$config" --list >/dev/null
done

if command -v fnox >/dev/null; then
  for config in fnox.toml fnox.work.toml; do
    FNOX_CONFIG_DIR=/nonexistent \
      fnox --non-interactive -c "$repo_root/$config" profiles >/dev/null
  done
fi

tests/bootstrap_test.sh
tests/github_pat_credential_test.sh

mise_bin="${MISE_BIN:-$(type -P mise 2>/dev/null || true)}"
if [[ -x "$mise_bin" ]]; then
  temp_home="$(mktemp -d)"
  trap 'rm -rf -- "$temp_home"' EXIT

  for profile in dev work; do
    mkdir -p "$temp_home/$profile"
    CI=1 \
      HOME="$temp_home/$profile" \
      MISE_TRUSTED_CONFIG_PATHS="$repo_root" \
      OP_SERVICE_ACCOUNT_TOKEN=test-placeholder-not-a-secret \
      "$mise_bin" -C "$repo_root" -E "$profile" \
      tasks validate --errors-only >/dev/null
    CI=1 \
      HOME="$temp_home/$profile" \
      MISE_TRUSTED_CONFIG_PATHS="$repo_root" \
      OP_SERVICE_ACCOUNT_TOKEN=test-placeholder-not-a-secret \
      "$mise_bin" -C "$repo_root" -E "$profile" \
      bootstrap --dry-run --skip tools,task,final-hook >/dev/null
  done

  mkdir -p "$temp_home/locked"
  CI=1 \
    HOME="$temp_home/locked" \
    MISE_DATA_DIR="$temp_home/locked-data" \
    MISE_CACHE_DIR="$temp_home/locked-cache" \
    MISE_STATE_DIR="$temp_home/locked-state" \
    MISE_OFFLINE=1 \
    MISE_TRUSTED_CONFIG_PATHS="$repo_root" \
    OP_SERVICE_ACCOUNT_TOKEN=test-placeholder-not-a-secret \
    "$mise_bin" -C "$repo_root" -E dev \
    bootstrap --dry-run --skip task,final-hook >/dev/null

  CI=1 \
    OP_SERVICE_ACCOUNT_TOKEN=test-placeholder-not-a-secret \
    MISE_TRUSTED_CONFIG_PATHS="$repo_root" \
    "$mise_bin" -C "$repo_root" -E dev fmt --all --check
fi

printf 'validation passed\n'
