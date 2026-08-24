#!/usr/bin/env bash
# Screen Time storage helper.
# Usage: store.sh <path>
# Reads JSON from stdin and writes it to <path>, creating parent dirs.
set -euo pipefail

target="${1:?usage: store.sh <path>}"

mkdir -p "$(dirname "$target")"

# Read one line (the JSON payload written by the plugin) then finish. Quickshell
# does not close the process stdin for us, so `cat` would block forever waiting
# for EOF; a single-line read returns as soon as the payload arrives.
IFS= read -r data || true

tmp="$(mktemp "${target}.XXXXXX")"
printf '%s' "$data" > "$tmp"
mv -f "$tmp" "$target"
