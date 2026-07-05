#!/usr/bin/env bash
set -euo pipefail
s="" d="$HOME/.claude/themes"
while [[ $# -gt 0 ]]; do case "$1" in
  --source) s="$2"; shift 2;;
  --dest) d="$2"; shift 2;;
  *) echo "unknown option: $1" >&2; exit 1;;
esac; done
p="${BASH_SOURCE[0]}"; while [ -h "$p" ]; do dir="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"; [[ $p != /* ]] && p="$dir/$p"; done
r="$(cd -P "$(dirname "$p")" && pwd)"
[ -z "$s" ] && s="$r/catppuccin"
[ -d "$d" ] || { mkdir -p "$d"; echo "created $d"; }
shopt -s nullglob; t=("$s"/catppuccin-*.json); shopt -u nullglob
[ ${#t[@]} -eq 0 ] && { echo "warning: no catppuccin-*.json found in $s" >&2; exit 0; }
for f in "${t[@]}"; do cp -f "$f" "$d/"; echo "installed $(basename "$f")"; done
echo -e "\n${#t[@]} themes installed to $d. Run /theme to select one."
