#!/usr/bin/env bash
# Extracts the Perl hook Brim installs into Claude Code and checks that it compiles.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$(mktemp -t brim-hook).pl"
trap 'rm -f "$script"' EXIT
sed -n '/static let source = #"""/,/"""#/p' Brim/Agents/HookScript.swift | sed '1d;$d' | sed 's/^    //' > "$script"
/usr/bin/perl -c "$script"
