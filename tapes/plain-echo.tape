# plain-echo.tape — INTRO.md "Example: Echo", no-subbit only for now.
#
# Run with: vhs ./tapes/plain-echo.tape  (or: record-tape ./tapes/plain-echo.tape)

Require tmux
Require tmuxp

Output out/plain-echo.webm

Set Shell "bash"
Set FontSize 16
Set Width 1400
Set Height 800
Set WaitTimeout 10s
Set WaitPattern /\[typist\] > /

# hidden: reset leftover session, load tmux, wait for it 
Hide
Type "tmux kill-session -t echo-demo 2>/dev/null; printf '\033c'"
Enter
Type "tmuxp load ./tmux/echo.yaml"
Enter
Wait+Screen
Show

# --- server ---
Type "pane server"
Enter
Wait+Screen
Sleep 200ms

Type "as echo-server"
Enter
Wait+Screen /echo_server: Starting/
Sleep 200ms

# --- client ---
Type "pane client"
Enter
Wait+Screen
Sleep 200ms

Type "run echo-client init"
Enter
Wait+Screen
Sleep 200ms

# --data omitted: consumer decides the default via into_sources
Type "as echo-client send"
Enter
# server logs "response given status=200 body_len=15"
Wait+Screen /status=200/
Sleep 1s

# hidden teardown: remove pane workdirs, then kill the session
Hide
Type "demo-clean"
Enter
Type "tmux kill-session -t echo-demo"
Enter
