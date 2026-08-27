# tmux/aliases.sh — sourced by every pane (typist + each spawned actor).
#
# Model: one FOCUSED pane (50% width, full height above typist's footer)
# and a SIDEBAR of every other pane, stacked vertically in the other half.
# Typist only ever manages panes (pane/focus/close) or acts on
# whichever pane is focused (run/as/signal) — nothing is addressed by name
# except pane/focus, which need to say *which* sidebar pane.
#
# State: _FOCUS (pane_id in the focus slot), _SIDEBAR (array of pane_ids,
# stack order, last = most recently demoted), _PANE_NAME (pane_id -> name,
# for _pane_wait_ready's prompt regex). $<NAME>_PANE/$<NAME>_DIR are also
# set per pane (used by `focus`, and for direct pane_id/workdir access).
#
# swap-pane trades CONTENT+SIZE between two panes without touching either
# pane_id — that's what makes focus changes cheap: promoting a pane is
# one swap-pane call, no relayout. ALWAYS pass -d: without it, swap-pane
# also moves tmux's actual active pane, which steals keystrokes away from
# typist (the real bug behind a stall that looks like "commands went to
# the wrong pane").
#
# subbit-xyz binaries (echo-server, echo-client, echo-proxy, mock-index,
# subbit-cli, subbit-server) are on PATH directly via the devShell
# (flake.nix) 

# tomlset <file> <path> <value> : set path.to.value in a toml file. 
tomlset() {
  if [ "$#" -ne 3 ]; then
    echo "usage: tomlset <file> <path> <value>" >&2
    return 1
  fi
  local path="$2" value="$3" expr
  if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [ "$value" = "true" ] || [ "$value" = "false" ]; then
    expr=".$path = $value"
  else
    expr=".$path = \"$value\""
  fi
  yq -i -p toml -o toml "$expr" "$1" || {
    echo "tomlset: yq failed (exit $?) on $1" >&2
    return 1
  }
}

_FOCUS=""
_SIDEBAR=()
declare -A _PANE_NAME
_PANE_DIRS=()

# redraw — repin typist's footer height and equalize sidebar pane heights
# against the focus pane's current height. Call after any pane/focus
# change, or manually after a real terminal resize.
redraw() {
  [ -z "$_FOCUS" ] && return 0
  tmux resize-pane -t "$TMUX_PANE" -y 4 2>/dev/null
  local n="${#_SIDEBAR[@]}"
  [ "$n" -eq 0 ] && return 0
  local total base rem i h last=$((n - 1))
  total=$(tmux display-message -t "$_FOCUS" -p '#{pane_height}')
  base=$((total / n))
  rem=$((total % n))
  for i in "${!_SIDEBAR[@]}"; do
    [ "$i" -eq "$last" ] && continue
    h=$((base + (i < rem ? 1 : 0)))
    tmux resize-pane -t "${_SIDEBAR[$i]}" -y "$h"
  done
}

# _pane_wait_ready PANE_ID NAME — poll until that pane's own idle prompt
# "[NAME] > " is the last non-blank line. Needed because `tmux send-keys`
# is fire-and-forget. Never call against a long-running process — use `as`.
_pane_wait_ready() {
  local id="$1" name="$2" tries=0 line
  while [ "$tries" -lt 100 ]; do
    line="$(tmux capture-pane -t "$id" -p | grep -v '^[[:space:]]*$' | tail -n 1)"
    if [[ "$line" =~ ^\[${name}\][[:space:]]*\>[[:space:]]*$ ]]; then
      return 0
    fi
    sleep 0.1
    tries=$((tries + 1))
  done
  echo "_pane_wait_ready: timed out waiting for '$name' (last line seen: '$line')" >&2
  return 1
}

# pane NAME — create a pane in a fresh throwaway workdir and focus it.
#   1st ever: split typist (-b), pin typist as footer. Sole pane = focus.
#   2nd ever: split focus 50/50 -> first sidebar slot.
#   3rd+:     append below the sidebar stack.
# In all but the first case, whatever was focus gets swap-pane'd into the
# slot the new pane was just created in, so the new pane ends up focused.
pane() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "usage: pane <name>" >&2
    return 1
  fi
  local id workdir was_focus="$_FOCUS"
  workdir=$(mktemp -d)

  if [ -z "$was_focus" ]; then
    id=$(tmux split-window -v -b -d -P -F '#{pane_id}')
  elif [ "${#_SIDEBAR[@]}" -eq 0 ]; then
    id=$(tmux split-window -h -t "$was_focus" -d -P -F '#{pane_id}')
    _SIDEBAR+=("$id")
  else
    id=$(tmux split-window -v -t "${_SIDEBAR[$((${#_SIDEBAR[@]} - 1))]}" -d -P -F '#{pane_id}')
    _SIDEBAR+=("$id")
  fi

  tmux select-pane -t "$id" -T "$name"
  tmux send-keys -t "$id" \
    "cd \"$workdir\"; unset PROMPT_COMMAND; PS1='[$name] > '; source $(pwd)/tmux/aliases.sh; printf '\033c'" Enter
  _pane_wait_ready "$id" "$name"

  _PANE_DIRS+=("$workdir")
  _PANE_NAME["$id"]="$name"
  printf -v "$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_PANE" '%s' "$id"
  printf -v "$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_DIR" '%s' "$workdir"

  if [ -n "$was_focus" ]; then
    tmux swap-pane -d -s "$id" -t "$was_focus"
    _SIDEBAR[$((${#_SIDEBAR[@]} - 1))]="$was_focus"
  fi
  _FOCUS="$id"
  redraw
}

# focus NAME — promote a sidebar pane to focus. swap-pane relocates it
# physically (content+size trade with current focus); the stack itself
# treats this as pop-target + push-old-focus, same LIFO end close
# pops from — so "most recently unfocused" is always well-defined
# regardless of where the promoted pane came from. No-op if already focused.
focus() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "usage: focus <name>" >&2
    return 1
  fi
  local varname id idx=-1 i
  varname="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_PANE"
  id="${!varname}"
  if [ -z "$id" ]; then
    echo "focus: no pane named '$name'" >&2
    return 1
  fi
  if [ "$id" = "$_FOCUS" ]; then
    return 0
  fi
  for i in "${!_SIDEBAR[@]}"; do
    if [ "${_SIDEBAR[$i]}" = "$id" ]; then
      idx="$i"
      break
    fi
  done
  if [ "$idx" -lt 0 ]; then
    echo "focus: '$name' is not a sidebar pane" >&2
    return 1
  fi
  tmux swap-pane -d -s "$id" -t "$_FOCUS"
  _SIDEBAR=("${_SIDEBAR[@]:0:$idx}" "${_SIDEBAR[@]:$((idx + 1))}")
  _SIDEBAR+=("$_FOCUS")
  _FOCUS="$id"
  redraw
}

# close — close the FOCUSED pane (no name: same convention as
# signal/run/as). Interrupts it via `signal` first, best-effort. If a
# sidebar exists, promotes the most-recently-demoted pane (bottom of
# _SIDEBAR) into focus before killing, so the closing pane dies in that
# now-vacated sidebar slot rather than in the focus slot.
close() {
  if [ -z "$_FOCUS" ]; then
    echo "close: nothing focused" >&2
    return 1
  fi
  local id="$_FOCUS" name="${_PANE_NAME[$_FOCUS]}"
  signal C-c 2>/dev/null
  sleep 0.2

  if [ "${#_SIDEBAR[@]}" -gt 0 ]; then
    local last=$((${#_SIDEBAR[@]} - 1))
    local promote="${_SIDEBAR[$last]}"
    tmux swap-pane -d -s "$promote" -t "$_FOCUS"
    tmux kill-pane -t "$id" 2>/dev/null
    _SIDEBAR=("${_SIDEBAR[@]:0:$last}")
    _FOCUS="$promote"
  else
    tmux kill-pane -t "$id" 2>/dev/null
    _FOCUS=""
  fi

  unset "$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_PANE"
  unset "_PANE_NAME[$id]"
  redraw
}

# demo-clean — remove every pane workdir this typist created via `pane`
demo-clean() {
  local d n=0
  for d in "${_PANE_DIRS[@]}"; do
    rm -rf "$d" && n=$((n + 1))
  done
  echo "demo-clean: removed $n workdir(s)"
  _PANE_DIRS=()
}

# signal KEY... — raw tmux key(s) to the focused pane, e.g. `signal C-c`.
signal() {
  if [ "$#" -eq 0 ]; then
    echo "usage: signal <key...>" >&2
    return 1
  fi
  if [ -z "$_FOCUS" ]; then
    echo "signal: nothing focused" >&2
    return 1
  fi
  tmux send-keys -t "$_FOCUS" "$@"
}

# as CMD... — fire-and-forget to the focused pane. Use ONLY for starting a
# long-running/foreground process (never returns a prompt); confirm success
# via a content-specific Wait+Screen in the tape.
as() {
  if [ "$#" -eq 0 ]; then
    echo "usage: as <command...>" >&2
    return 1
  fi
  if [ -z "$_FOCUS" ]; then
    echo "as: nothing focused" >&2
    return 1
  fi
  tmux send-keys -t "$_FOCUS" "$*" Enter
}

# run CMD... — blocks until the focused pane returns to its own idle
# prompt. Use for one-shot commands; never for a long-running service.
run() {
  if [ "$#" -eq 0 ]; then
    echo "usage: run <command...>" >&2
    return 1
  fi
  if [ -z "$_FOCUS" ]; then
    echo "run: nothing focused" >&2
    return 1
  fi
  tmux send-keys -t "$_FOCUS" "$*" Enter
  _pane_wait_ready "$_FOCUS" "${_PANE_NAME[$_FOCUS]}"
}
