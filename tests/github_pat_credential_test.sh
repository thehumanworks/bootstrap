#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_token='github_pat_test-only-not-a-secret'
helper="!f() { if [ \"\$1\" = get ]; then printf \"%s\\n\" \"username=x-access-token\" \"password=\$GH_TOKEN\"; fi; }; f"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home"

credentials="$({
  printf 'protocol=https\n'
  printf 'host=github.com\n\n'
} | HOME="$tmp/home" \
  XDG_CONFIG_HOME="$tmp/home/.config" \
  GH_TOKEN="$test_token" \
  GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=credential.https://github.com.helper \
  GIT_CONFIG_VALUE_0='' \
  GIT_CONFIG_KEY_1=credential.https://github.com.helper \
  GIT_CONFIG_VALUE_1="$helper" \
  GIT_CONFIG_KEY_2=credential.interactive \
  GIT_CONFIG_VALUE_2=never \
  git credential fill)"

grep -Fxq 'protocol=https' <<<"$credentials" ||
  fail 'credential protocol was not preserved'
grep -Fxq 'host=github.com' <<<"$credentials" ||
  fail 'credential host was not preserved'
grep -Fxq 'username=x-access-token' <<<"$credentials" ||
  fail 'credential username is missing'
grep -Fxq "password=$test_token" <<<"$credentials" ||
  fail 'PAT was not supplied as the credential password'

[[ "$helper" == *GH_TOKEN* ]] ||
  fail 'helper does not defer PAT lookup to runtime'
[[ "$helper" != *"$test_token"* ]] ||
  fail 'helper embeds the PAT value'
mapfile -t persisted_files < <(find "$tmp" -type f -print)
((${#persisted_files[@]} == 0)) ||
  fail 'the environment-only helper wrote under the test home'

printf 'GitHub PAT credential-helper tests passed\n'
