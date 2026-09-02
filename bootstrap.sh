#!/usr/bin/env bash
set -euo pipefail

environment="${1:-dev}"
mise bootstrap --env "$environment" --yes --force-dotfiles
