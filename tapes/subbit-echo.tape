# Run with: vhs ./tapes/subbit-echo.tape

Require tmux
Require tmuxp

Output out/subbit-echo.webm

Set Shell "bash"
Set FontSize 14
Set Width 1600
Set Height 1000
Set WaitTimeout 10s

Set WaitPattern /\[typist\] > /

Hide
Type "tmux kill-session -t echo-demo 2>/dev/null; clear"
Enter
Type "tmuxp load ./tmux/echo.yaml"
Enter
Wait+Screen
Show

# --- provider ---
Type "pane provider"
Enter
Wait+Screen
Sleep 200ms

Type "run subbit-server init"
Enter
Wait+Screen
Sleep 200ms

Type "run tomlset ./subbit-server-config.toml db.db_path ./subbit.redb"
Enter
Wait+Screen
Sleep 200ms

Type "as subbit-server serve"
Enter
# FIXME : Make this more robust!
Wait+Screen /subbit_server: Starting/
Sleep 200ms

# --- echo-proxy ---
Type "pane echo-proxy"
Enter
Wait+Screen
Sleep 200ms

Type "run echo-proxy init"
Enter
Wait+Screen
Sleep 200ms

Type "as echo-proxy run"
Enter
Wait+Screen /echo_proxy::cli: Starting/
Sleep 200ms

# --- echo-server ---
Type "pane echo-server"
Enter
Wait+Screen
Sleep 200ms

Type "as echo-server"
Enter
Wait+Screen /echo_server: Starting/
Sleep 200ms

# --- consumer: own init, own keys, own ledger row ---
Type "pane consumer"
Enter
Wait+Screen
Sleep 200ms

Type "run echo-client init"
Enter
Wait+Screen
Sleep 200ms

Type "run tomlset ./echo-client-config.toml subbit.cache ./subbit-state.cbor"
Enter
Wait+Screen
Sleep 200ms

Type "run tomlset ./echo-client-config.toml base_url http://127.0.0.1:6432"
Enter
Wait+Screen
Sleep 200ms

# FIXME: config's own default (0) is itself wrong and needs fixing
# upstream
Type "run tomlset ./echo-client-config.toml subbit.cost.default 5"
Enter
Wait+Screen
Sleep 200ms

Type "run subbit-cli init"
Enter
Wait+Screen
Sleep 200ms

Type "run 'IOU=$(subbit-cli keyring generate iou); IOU_VK=$(echo $IOU | jq -r .vk); IOU_SK=$(echo $IOU | jq -r .sk); KEYTAG=${IOU_VK}deadbeef; echo $KEYTAG,10000000,0 > /tmp/mock-ledger.csv'"
Enter
Wait+Screen
Sleep 200ms

# tag left at its config default ("deadbeef") 
Type "run 'tomlset ./echo-client-config.toml subbit.issuer.account.signing_key $IOU_SK'"
Enter
Wait+Screen
Sleep 200ms

# --- index: bring up only to submit consumer's ledger row, then close ---
Type "pane index"
Enter
Wait+Screen
Sleep 200ms

Type "run mock-index --file /tmp/mock-ledger.csv"
Enter
Wait+Screen
Sleep 200ms

Type "close"
Enter
Wait+Screen
Sleep 200ms

# --- consumer (back in focus) sends ---
Type "as echo-client send"
Enter
# Targets echo-server's OWN log line ("response given status=200 ..."),
# not echo-client's own output (which just returns to the prompt).
Wait+Screen /status=200/
Sleep 1s

Hide
Type "demo-clean"
Enter
Type "rm -f /tmp/mock-ledger.csv /tmp/subbit-state.cbor"
Enter
Type "tmux kill-session -t echo-demo"
Enter
