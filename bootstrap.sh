#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  bootstrap.sh [PROFILE] [--] [MISE_BOOTSTRAP_ARG...]
  bootstrap.sh --profile PROFILE [--] [MISE_BOOTSTRAP_ARG...]

Run mise bootstrap from this checkout, regardless of the current directory.
PROFILE defaults to dev. Arguments after PROFILE are forwarded to mise.

Examples:
  ./bootstrap.sh
  ./bootstrap.sh dev --dry-run
  ./bootstrap.sh work --force-dotfiles
  ./bootstrap.sh --profile dev --update

This wrapper requires an existing checkout and an installed mise. For a fresh
sandbox, use `mise bootstrap --from`; see README.md.
EOF
}

script_dir="$(
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)" || die "could not resolve the repository directory"
readonly script_dir

profile="${BOOTSTRAP_PROFILE:-dev}"

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  -p | --profile)
    (($# >= 2)) || die "$1 requires a profile name"
    profile="$2"
    shift 2
    ;;
  --profile=*)
    profile="${1#*=}"
    shift
    ;;
  --)
    shift
    ;;
  -* | "") ;;
  *)
    profile="$1"
    shift
    ;;
esac

if [[ "${1:-}" == "--" ]]; then
  shift
fi

[[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
  die "invalid profile '$profile'; use letters, digits, '_' or '-'"

profile_file="$script_dir/mise.$profile.toml"
if [[ ! -f "$profile_file" ]]; then
  available=()
  for candidate in "$script_dir"/mise.*.toml; do
    [[ -f "$candidate" ]] || continue
    name="${candidate##*/}"
    name="${name#mise.}"
    name="${name%.toml}"
    [[ "$name" == *.* ]] || available+=("$name")
  done

  if ((${#available[@]})); then
    printf "bootstrap: unknown profile '%s'; available:" "$profile" >&2
    printf ' %s' "${available[@]}" >&2
    printf '\n' >&2
    exit 1
  fi
  die "unknown profile '$profile'; no mise.<profile>.toml files found"
fi

mise_bin=""
if [[ -n "${MISE_BIN:-}" ]]; then
  if [[ "$MISE_BIN" == */* ]]; then
    [[ -x "$MISE_BIN" ]] || die "MISE_BIN is not executable: $MISE_BIN"
    mise_bin="$MISE_BIN"
  else
    mise_bin="$(type -P "$MISE_BIN" 2>/dev/null || true)"
    [[ -n "$mise_bin" ]] || die "MISE_BIN command was not found: $MISE_BIN"
  fi
else
  mise_bin="$(type -P mise 2>/dev/null || true)"
  if [[ -z "$mise_bin" && -n "${HOME:-}" && -x "$HOME/.local/bin/mise" ]]; then
    mise_bin="$HOME/.local/bin/mise"
  fi
fi

if [[ -z "$mise_bin" ]]; then
  cat >&2 <<'EOF'
bootstrap: mise is required but was not found.

Install it with:
  curl -fsSL https://mise.run | sh

Then rerun this script, or use the README's fresh-sandbox command.
EOF
  exit 127
fi

exec "$mise_bin" -C "$script_dir" -E "$profile" bootstrap --yes "$@"

