#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
	echo "cua:setup requires Apple Silicon macOS." >&2
	exit 1
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cua_source="${CUA_LOCAL_SOURCE:-$repo_dir/tools/cua-local}"
if [[ -z "${CUA_LOCAL_SOURCE:-}" && ! -d "$cua_source/cua_local" ]]; then
	cua_source="$HOME/projects/cua-local"
fi
if [[ ! -f "$cua_source/requirements.lock" || ! -d "$cua_source/cua_local" ]]; then
	echo "Cua source not found; set CUA_LOCAL_SOURCE to the directory containing cua_local/ and requirements.lock." >&2
	exit 1
fi
cua_home="${CUA_LOCAL_HOME:-$HOME/.local/share/cua-local}"
mkdir -p "$cua_home" "$HOME/.local/bin"
if [[ ! -x "$cua_home/venv/bin/python" ]]; then
	uv venv --python 3.13 "$cua_home/venv"
fi
uv pip sync --python "$cua_home/venv/bin/python" "$cua_source/requirements.lock"
env -u HF_HUB_OFFLINE PYTHONPATH="$cua_source" HF_HUB_DISABLE_TELEMETRY=1 \
	"$cua_home/venv/bin/python" -c 'from cua_local.config import download; download()'
"$cua_home/venv/bin/python" -m playwright install chromium

# Use the pinned, upstream installer for the signed macOS app/TCC identity.
# Do not replace a user's newer native driver or restart an existing daemon.
if ! command -v cua-driver >/dev/null 2>&1; then
	install_dir="$cua_home/installer"
	mkdir -p "$install_dir"
	source_revision=605d358a48ad938a41b384a8f23909153eb73f78
	for name in install.sh _install-rust.sh _install-common.sh; do
		curl -fsSL "https://raw.githubusercontent.com/trycua/cua/$source_revision/libs/cua-driver/scripts/$name" -o "$install_dir/$name"
	done
	CUA_DRIVER_RS_VERSION=0.28.2 CUA_DRIVER_RS_TELEMETRY_ENABLED=0 \
		bash "$install_dir/install.sh" --no-modify-path
	"$HOME/.local/bin/cua-driver" telemetry disable
fi
if [[ -e "$HOME/.local/bin/cua-local" && ! "$HOME/.local/bin/cua-local" -ef "$repo_dir/scripts/cua-local" ]]; then
	echo "Refusing to replace existing ~/.local/bin/cua-local" >&2
	exit 1
fi
chmod +x "$repo_dir/scripts/cua-local"
ln -sfn "$repo_dir/scripts/cua-local" "$HOME/.local/bin/cua-local"
echo "Ready: cua-local demo | cua-local doctor | cua-local --help"
echo "Native apps additionally need: cua-driver permissions grant"
