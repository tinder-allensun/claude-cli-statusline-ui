#!/bin/bash
# Claude Code status line, exactly three lines:
#   1. Project:  ➜  <folder> git:(<branch>)
#   2. Context:  <model> <bar> <used>/<max> (<pct>%)
#   3. Cache:    Money Saver, from prompt_cache (Claude Code >= 2.1.251)
#
# Test hooks: STATUSLINE_NOW overrides the clock (epoch seconds).

input=$(cat)

# ${#s} and ${s:i:1} must count characters, not bytes, for truncation. Status line processes
# may start with no locale, so force a UTF-8 one (en_US on macOS, C.UTF-8 on most Linux).
case "$(locale charmap 2>/dev/null)" in
  UTF-8) ;;
  *) export LC_ALL=en_US.UTF-8; [ "$(locale charmap 2>/dev/null)" = UTF-8 ] || export LC_ALL=C.UTF-8 ;;
esac

RESET=$'\033[0m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[32m'
AMBER=$'\033[38;5;214m'
BLUE=$'\033[1;34m'
CYAN=$'\033[36m'
BGREEN=$'\033[1;32m'

BAR_WIDTH=20
GIT_TTL=5

# ---------------------------------------------------------------- helpers

# trunc <string> <max>: cut to <max> visible columns with a trailing "…", keeping ANSI SGR intact.
trunc() {
  local s=$1 max=$2 n=${#1} i c vis=0 esc=0 out=''
  [ "$max" -gt 0 ] 2>/dev/null || { printf '%s' "$s"; return; }
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [ $esc = 1 ]; then [ "$c" = m ] && esc=0; continue; fi
    if [ "$c" = $'\033' ]; then esc=1; continue; fi
    vis=$((vis + 1))
  done
  if [ $vis -le "$max" ]; then printf '%s' "$s"; return; fi
  vis=0 esc=0
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [ $esc = 1 ]; then out+=$c; [ "$c" = m ] && esc=0; continue; fi
    if [ "$c" = $'\033' ]; then esc=1; out+=$c; continue; fi
    [ $vis -ge $((max - 1)) ] && break
    out+=$c
    vis=$((vis + 1))
  done
  printf '%s…%s' "$out" "$RESET"
}

# fmt_tok <int>: 950 -> 950, 161400 -> 161.4k, 200000 -> 200k, 1000000 -> 1M
fmt_tok() {
  local n=$1 t
  if [ "$n" -ge 1000000 ]; then
    t=$((n / 100000)); fmt_dec "$t" M
  elif [ "$n" -ge 1000 ]; then
    t=$((n / 100)); fmt_dec "$t" k
  else
    printf '%s' "$n"
  fi
}
# fmt_dec <tenths> <suffix>: 1614 k -> 161.4k, 2000 k -> 200k
fmt_dec() {
  if [ $(($1 % 10)) -eq 0 ]; then printf '%s%s' "$(($1 / 10))" "$2"; else printf '%s.%s%s' "$(($1 / 10))" "$(($1 % 10))" "$2"; fi
}

is_int() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# bar <filled>: BAR_WIDTH cells, <filled> of them solid
bar() {
  local f=$1 i b=''
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if [ $i -lt "$f" ]; then b+='▓'; else b+='░'; fi
  done
  printf '%s' "$b"
}

# git_branch <cwd> <session_id>: branch (or short sha), cached per session for GIT_TTL seconds.
git_branch() {
  local cwd=$1 sid=${2//[^A-Za-z0-9_-]/_} cf now mt line branch=''
  cf="${TMPDIR:-/tmp}/claude-statusline-git-${sid:-nosession}"
  cf=${cf//\/\//\/}
  now=$(date +%s)
  if [ -f "$cf" ]; then
    mt=$(stat -c %Y "$cf" 2>/dev/null || stat -f %m "$cf" 2>/dev/null)
    if is_int "$mt" && [ $((now - mt)) -lt $GIT_TTL ]; then
      IFS= read -r line <"$cf"
      if [ "${line%%$'\t'*}" = "$cwd" ]; then printf '%s' "${line#*$'\t'}"; return; fi
    fi
  fi
  if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
      || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  printf '%s\t%s\n' "$cwd" "$branch" >"$cf.$$" 2>/dev/null && mv -f "$cf.$$" "$cf" 2>/dev/null
  printf '%s' "$branch"
}

# ---------------------------------------------------------------- parse input

cwd='' sid='' mid='' mname='' win='' used='' pct='' cu='' pc='' observed='' warm='' ttl='' exp='' recache='' effort=''
if command -v jq >/dev/null 2>&1; then
  IFS=$'\x1f' read -r cwd sid mid mname win used pct cu pc observed warm ttl exp recache effort < <(
    printf '%s' "$input" | jq -r '
      def s: if . == null then "" else tostring end;
      (.prompt_cache | if type == "object" then . else {} end) as $p
      | [ ((.workspace.current_dir // .cwd) | s),
          (.session_id | s),
          (.model.id | s),
          (.model.display_name | s),
          (.context_window.context_window_size | s),
          (.context_window.total_input_tokens | s),
          (.context_window.used_percentage | s),
          (.context_window.current_usage
             | if type == "object"
               then ((.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
               else null end | s),
          (if (.prompt_cache | type) == "object" then "1" else "" end),
          ($p.caching_observed | s),
          ($p.warm | s),
          ($p.ttl | s),
          ($p.expires_at | s),
          ($p.recache_tokens_if_cold | s),
          (.effort.level | s)
        ] | join("\u001f")' 2>/dev/null
  )
fi

now=${STATUSLINE_NOW:-$(date +%s)}

# ---------------------------------------------------------------- line 1: project

[ -z "$cwd" ] && cwd=$PWD
dir=${cwd##*/}
[ -z "$dir" ] && dir=/
line1="${BGREEN}➜${RESET}  ${CYAN}${dir}${RESET}"
branch=$(git_branch "$cwd" "$sid")
[ -n "$branch" ] && line1="$line1 ${BLUE}git:(${RED}${branch}${BLUE})${RESET}"

# ---------------------------------------------------------------- line 2: context

used=${used%%.*} win=${win%%.*}
[ -z "$mname" ] && mname=Claude
[ -n "$effort" ] && mname="$mname ($effort)"
if is_int "$used" && is_int "$win" && [ "$used" -gt 0 ] && [ "$win" -gt 0 ]; then
  filled=$((used * BAR_WIDTH / win))
  [ $filled -gt $BAR_WIDTH ] && filled=$BAR_WIDTH
  if [ -n "$pct" ]; then pct_txt="$(printf '%.0f' "$pct" 2>/dev/null)%"; else pct_txt="—"; fi
  line2="$mname $(bar $filled) $(fmt_tok "$used")/$(fmt_tok "$win") (${pct_txt})"
else
  line2="$mname $(bar 0) —"
fi

# ---------------------------------------------------------------- line 3: money saver

exp=${exp%%.*}
is_warm=0
if [ "$pc" = 1 ] && [ "$observed" = true ]; then
  if [ "$warm" = true ]; then
    is_warm=1
    # Past its expiry the prefix is cold even if the payload still says warm.
    if is_int "$exp" && [ "$exp" -le "$now" ]; then is_warm=0; fi
  fi
fi

if [ "$pc" != 1 ] || [ "$observed" != true ]; then
  line3="${DIM}Prompt Cache Status: unavailable${RESET}"
else
  # Token count N: recache_tokens_if_cold, else last call's cache read + creation, else unknown.
  n=''
  if is_int "$recache"; then n=$recache; elif is_int "$cu"; then n=$cu; fi

  if [ $is_warm = 1 ]; then
    if [ -n "$n" ]; then tok="~$(fmt_tok "$n") tokens cached"; else tok="size unknown"; fi
    line3="Prompt Cache Status: Warm · $tok"
    if is_int "$exp"; then
      rem=$((exp - now))
      if [ $rem -lt 60 ]; then line3="$line3 · expires in <1m"; else line3="$line3 · expires in $((rem / 60))m"; fi
    fi
    line3="${GREEN}${line3}${RESET}"
  else
    if [ -n "$n" ]; then tok="~$(fmt_tok "$n") tokens to recache"; else tok="size unknown"; fi
    line3="Prompt Cache Status: Cold · $tok"
    line3="${AMBER}${line3}${RESET}"
  fi
fi

# ---------------------------------------------------------------- output

cols=${COLUMNS:-}
is_int "$cols" || cols=0
printf '%s\n' "$(trunc "$line1" "$cols")" "$(trunc "$line2" "$cols")" "$(trunc "$line3" "$cols")"
