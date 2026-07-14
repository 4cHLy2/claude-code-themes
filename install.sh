#!/usr/bin/env bash
set -euo pipefail

src="" dest="$HOME/.claude/themes" filter="*" list=0 all=0
families=()
while [[ $# -gt 0 ]]; do case "$1" in
  --source) src="$2"; shift 2;;
  --dest)   dest="$2"; shift 2;;
  --family) families+=("$2"); shift 2;;
  --filter) filter="$2"; shift 2;;
  --all)    all=1; shift;;
  --list)   list=1; shift;;
  *) echo "unknown option: $1" >&2; exit 1;;
esac; done

p="${BASH_SOURCE[0]}"
while [ -h "$p" ]; do d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"; [[ $p != /* ]] && p="$d/$p"; done
root="$(cd -P "$(dirname "$p")" && pwd)"

in_list() { local n="$1"; shift; local x; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

choose() {
  local title="$1"; shift
  local items=("$@") i=1 it ans tok idx found out=()
  if [ ${#items[@]} -le 1 ]; then printf '%s\n' "${items[@]}"; return; fi
  { echo ""; echo "$title"
    for it in "${items[@]}"; do echo "  $i) $it"; i=$((i+1)); done
    printf "Choose (comma-separated numbers or names, 'a' for all) [a]: "; } >&2
  IFS= read -r ans <&3 || ans=""
  if [ -z "$ans" ] || [ "$ans" = a ] || [ "$ans" = all ] || [ "$ans" = '*' ]; then
    printf '%s\n' "${items[@]}"; return
  fi
  ans="${ans//,/ }"
  read -ra toks <<<"$ans"
  for tok in "${toks[@]}"; do
    if [[ $tok =~ ^[0-9]+$ ]]; then
      idx=$((tok - 1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#items[@]} ]; then out+=("${items[$idx]}"); else echo "out of range: $tok" >&2; fi
    else
      found=0; for it in "${items[@]}"; do [ "$it" = "$tok" ] && { out+=("$it"); found=1; }; done
      [ "$found" -eq 1 ] || echo "unknown choice: $tok" >&2
    fi
  done
  if [ ${#out[@]} -eq 0 ]; then echo "nothing recognized; selecting all" >&2; printf '%s\n' "${items[@]}"; return; fi
  printf '%s\n' "${out[@]}" | awk '!seen[$0]++'
}

dirs=() prefixes=()
if [ -n "$src" ]; then
  dirs+=("$src"); prefixes+=("$(basename "$src")")
else
  for entry in "$root"/*/; do
    entry="${entry%/}"; name="$(basename "$entry")"
    case "$name" in .*) continue;; esac
    if [ ${#families[@]} -gt 0 ] && ! in_list "$name" "${families[@]}"; then continue; fi
    dirs+=("$entry"); prefixes+=("$name")
  done
fi

catalog=()
for i in "${!dirs[@]}"; do
  dir="${dirs[$i]}"; fam="${prefixes[$i]}"
  [ -d "$dir" ] || continue
  shopt -s nullglob
  for f in "$dir/$fam"-*.json; do
    base="$(basename "$f" .json)"
    rest="${base#"$fam"-}"
    flavor="${rest%%-*}"
    if [ "$rest" = "$flavor" ]; then accent=""; else accent="${rest#*-}"; fi
    catalog+=("$fam|$flavor|$accent|$f")
  done
  shopt -u nullglob
done

if [ ${#catalog[@]} -eq 0 ]; then
  echo "no themes found (source='$src' family='${families[*]:-}')" >&2
  exit 0
fi

scripted=0
if [ -n "$src" ] || [ ${#families[@]} -gt 0 ] || [ "$filter" != "*" ] || [ "$list" -eq 1 ] || [ "$all" -eq 1 ]; then scripted=1; fi
if [ "$scripted" -eq 0 ] && [ ! -t 0 ] && [ -z "${CCTHEME_INPUT:-}" ]; then
  echo "non-interactive shell and no selection given; installing all (use --family/--filter to narrow)" >&2
  scripted=1; all=1
fi

selected=()
if [ -n "$src" ] || [ ${#families[@]} -gt 0 ] || [ "$filter" != "*" ] || [ "$all" -eq 1 ]; then
  for row in "${catalog[@]}"; do
    f="${row##*|}"; base="$(basename "$f")"
    # shellcheck disable=SC2053
    [[ $base == $filter ]] && selected+=("$f")
  done
else
  if ! exec 3<"${CCTHEME_INPUT:-/dev/tty}"; then
    echo "no terminal available for interactive mode; use --all, --family, or --filter" >&2
    exit 1
  fi
  echo "=== Claude Code theme installer ===" >&2
  fams=(); while IFS= read -r l; do fams+=("$l"); done < <(printf '%s\n' "${catalog[@]}" | cut -d'|' -f1 | sort -u)
  pick_fams=(); while IFS= read -r l; do pick_fams+=("$l"); done < <(choose "Theme family:" "${fams[@]}")

  flavors=(); while IFS= read -r l; do flavors+=("$l"); done < <(
    for row in "${catalog[@]}"; do IFS='|' read -r fa fl _ _ <<<"$row"; in_list "$fa" "${pick_fams[@]}" && echo "$fl"; done | sort -u)
  pick_flavors=(); while IFS= read -r l; do pick_flavors+=("$l"); done < <(choose "Flavor(s):" "${flavors[@]}")

  accents=(); while IFS= read -r l; do [ -n "$l" ] && accents+=("$l"); done < <(
    for row in "${catalog[@]}"; do IFS='|' read -r fa fl ac _ <<<"$row"
      { in_list "$fa" "${pick_fams[@]}" && in_list "$fl" "${pick_flavors[@]}"; } && echo "$ac"; done | sort -u)
  if [ ${#accents[@]} -gt 0 ]; then
    pick_accents=(); while IFS= read -r l; do pick_accents+=("$l"); done < <(choose "Accent(s):" "${accents[@]}")
  else
    pick_accents=()
  fi

  for row in "${catalog[@]}"; do
    IFS='|' read -r fa fl ac path <<<"$row"
    in_list "$fa" "${pick_fams[@]}" || continue
    in_list "$fl" "${pick_flavors[@]}" || continue
    if [ ${#accents[@]} -gt 0 ]; then in_list "$ac" "${pick_accents[@]}" || continue; fi
    selected+=("$path")
  done
fi

if [ ${#selected[@]} -eq 0 ]; then echo "no themes matched your selection" >&2; exit 0; fi

sorted=(); while IFS= read -r l; do sorted+=("$l"); done < <(printf '%s\n' "${selected[@]}" | sort)
selected=("${sorted[@]}")

if [ "$list" -eq 1 ]; then
  echo "${#selected[@]} theme(s) match:"
  for f in "${selected[@]}"; do echo "  $(basename "$f")"; done
  exit 0
fi

if [ "$scripted" -eq 0 ]; then
  printf "\nInstall %d theme(s) to %s? [Y/n]: " "${#selected[@]}" "$dest" >&2
  IFS= read -r c <&3 || c=""
  case "$c" in ""|y|Y|yes|YES) ;; *) echo "cancelled." >&2; exit 0;; esac
fi

[ -d "$dest" ] || { mkdir -p "$dest"; echo "created $dest"; }
for f in "${selected[@]}"; do cp -f "$f" "$dest/"; echo "installed $(basename "$f")"; done
echo -e "\n${#selected[@]} themes installed to $dest. Run /theme to select one."
