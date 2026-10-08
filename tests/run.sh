#!/usr/bin/env bash
# Self-contained tests: a fake CLAUDE_CONFIG_DIR and a stub "real" claude. Never touches ~/.claude.
#   tests/run.sh
set -uo pipefail
[ -n "${TRACE:-}" ] && set -x

root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d "${TMPDIR:-/tmp}/claude-shim-test.XXXXXX")
t=$(cd "$t" && pwd)   # collapse "//" (macOS TMPDIR ends in /)
trap 'rm -rf "$t"' EXIT

export CLAUDE_CONFIG_DIR=$t/claude
export HOME=$t/home
mkdir -p "$HOME/work/a_b" "$HOME/work/dest" "$CLAUDE_CONFIG_DIR"/{projects,sessions,file-history,session-env} "$t/stub"

# Stub real claude: records calls; `agents --json --all` returns $t/agents.json
cat > "$t/stub/claude" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$t/calls"
if [ "\$1 \$2" = "agents --json" ]; then cat "$t/agents.json" 2>/dev/null || echo '[]'; fi
EOF
chmod +x "$t/stub/claude"
echo '[]' > "$t/agents.json"
export PATH="$root/bin:$t/stub:$PATH"

pass=0 fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/     /'; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

enc() { sed 's#[^A-Za-z0-9]#-#g' <<<"$1"; }

# make_session <id> <cwd> <title> [text]
make_session() {
  local id=$1 cwd=$2 title=$3 text=${4:-hello} d
  d=$CLAUDE_CONFIG_DIR/projects/$(enc "$cwd"); mkdir -p "$d/$id/subagents" "$d/memory"
  {
    printf '{"type":"user","cwd":"%s","sessionId":"%s","message":{"content":"%s"}}\n' "$cwd" "$id" "$text"
    printf '{"type":"assistant","cwd":"%s","sessionId":"%s","message":{"content":[{"type":"text","text":"reply about %s"}]}}\n' "$cwd" "$id" "$text"
    printf '{"type":"custom-title","customTitle":"%s","sessionId":"%s"}\n' "$title" "$id"
  } > "$d/$id.jsonl"
  echo '{}' > "$d/$id/subagents/agent-x.jsonl"
  mkdir -p "$CLAUDE_CONFIG_DIR/file-history/$id" "$CLAUDE_CONFIG_DIR/session-env/$id"
}

A=aaaaaaaa-1111-2222-3333-444444444444
B=bbbbbbbb-1111-2222-3333-444444444444
C=cccccccc-1111-2222-3333-444444444444
make_session $A "$HOME/work/a_b" "alpha session" "kiwi fruit"
make_session $B "$HOME/work/a_b" "beta" "mango"
make_session $C "$HOME/work/a_b" "bg review" "papaya"
pdir=$CLAUDE_CONFIG_DIR/projects/$(enc "$HOME/work/a_b")

# passthrough
claude --version >/dev/null; check "passthrough reaches real claude" grep -qx -- "--version" "$t/calls"
check "claude shim reports" sh -c "claude shim | grep -q 'real claude: $t/stub/claude'"

# search
out=$(cd "$HOME/work/a_b" && claude search --no-color -d . kiwi 2>&1)
if grep -q "session: $A" <<<"$out" && grep -q "title:   alpha session" <<<"$out" && ! grep -q $B <<<"$out"; then ok "search -d . by pattern"; else bad "search -d . by pattern" "$out"; fi
out=$(claude search --no-color -o kiwi mango 2>&1)
if grep -q $A <<<"$out" && grep -q $B <<<"$out"; then ok "search OR mode"; else bad "search OR mode" "$out"; fi

# ls: current dir, explicit dir, recursive, status and name
mkdir -p "$HOME/work/a_b/sub"
D=dddddddd-1111-2222-3333-444444444444
make_session $D "$HOME/work/a_b/sub" "deeper" "guava"
printf '{"type":"agent-name","agentName":"lane-dev","sessionId":"%s"}\n' $B >> "$pdir/$B.jsonl"
sleep 300 & ls_pid=$!
printf '{"pid":%s,"sessionId":"%s","kind":"bg","name":"x"}\n' $ls_pid $B > "$CLAUDE_CONFIG_DIR/sessions/$ls_pid.json"
out=$(cd "$HOME/work/a_b" && claude ls --no-color 2>&1)
if grep -q "session: $A" <<<"$out" && grep -q "session: $B" <<<"$out" && ! grep -q $D <<<"$out"; then ok "ls lists current dir only"; else bad "ls lists current dir only" "$out"; fi
if grep -q "name:    lane-dev" <<<"$out" && grep -q "\[background\]" <<<"$out"; then ok "ls shows name and background status"; else bad "ls shows name and background status" "$out"; fi
out=$(claude ls --no-color -r "$HOME/work" 2>&1)
if grep -q $D <<<"$out" && grep -q $A <<<"$out"; then ok "ls -r includes subdirs"; else bad "ls -r includes subdirs" "$out"; fi
out=$(claude ls --no-color "$HOME/work" 2>&1); check "ls hints -r when dir has none" grep -q "claude ls -r" <<<"$out"
kill $ls_pid 2>/dev/null; wait $ls_pid 2>/dev/null; rm -f "$CLAUDE_CONFIG_DIR/sessions/$ls_pid.json"

# rm: dry run, by name
out=$(claude rm -n "beta" 2>&1)
if grep -q "dry run" <<<"$out" && [ -e "$pdir/$B.jsonl" ]; then ok "rm -n changes nothing"; else bad "rm -n changes nothing" "$out"; fi

# rm: ambiguous prefix
out=$(claude rm -n zzzz 2>&1); check "rm unknown session fails" grep -q "no session matches" <<<"$out"

# rm: live interactive session refused
sleep 300 & live_pid=$!
printf '{"pid":%s,"sessionId":"%s","kind":"interactive"}\n' $live_pid $B > "$CLAUDE_CONFIG_DIR/sessions/$live_pid.json"
out=$(claude rm -y beta 2>&1)
if grep -q "is open" <<<"$out" && [ -e "$pdir/$B.jsonl" ]; then ok "rm refuses open session"; else bad "rm refuses open session" "$out"; fi
kill $live_pid 2>/dev/null; wait $live_pid 2>/dev/null; rm -f "$CLAUDE_CONFIG_DIR/sessions/$live_pid.json"

# rm: by id prefix, removes all session files, keeps memory/
claude rm -y aaaaaaaa >/dev/null 2>&1
if [ ! -e "$pdir/$A.jsonl" ] && [ ! -e "$pdir/$A" ] && [ ! -e "$CLAUDE_CONFIG_DIR/file-history/$A" ] \
   && [ ! -e "$CLAUDE_CONFIG_DIR/session-env/$A" ] && [ -d "$pdir/memory" ]; then ok "rm deletes session files, keeps memory/"
else bad "rm deletes session files, keeps memory/"; fi

# rm: background session goes through real claude rm first
printf '[{"sessionId":"%s","kind":"background","name":"bg review"}]\n' $C > "$t/agents.json"
claude rm -y "bg review" >/dev/null 2>&1
if grep -qx "rm cccccccc" "$t/calls" && [ ! -e "$pdir/$C.jsonl" ]; then ok "rm background calls real rm"; else bad "rm background calls real rm" "$(cat "$t/calls")"; fi

# mv: background refused
make_session $C "$HOME/work/a_b" "bg review" "papaya"
out=$(claude mv cccccccc "$HOME/work/dest" 2>&1); check "mv refuses background session" grep -q "background session" <<<"$out"
echo '[]' > "$t/agents.json"

# mv: moves jsonl + session dir to the encoded destination
claude mv beta "$HOME/work/dest" >/dev/null 2>&1
ddir=$CLAUDE_CONFIG_DIR/projects/$(enc "$HOME/work/dest")
if [ -e "$ddir/$B.jsonl" ] && [ -e "$ddir/$B/subagents/agent-x.jsonl" ] && [ ! -e "$pdir/$B.jsonl" ]; then ok "mv moves transcript and session dir"
else bad "mv moves transcript and session dir"; fi
out=$(claude mv beta /definitely/not/here 2>&1); check "mv rejects missing dir" grep -q "no such directory" <<<"$out"

# installer: copy into a temp prefix with --no-rc, then uninstall
out=$("$root/install.sh" --prefix "$t/prefix" --no-rc 2>&1)
if [ -x "$t/prefix/bin/claude" ] && [ -f "$t/prefix/libexec/portable.sh" ]; then ok "install --prefix --no-rc"; else bad "install --prefix --no-rc" "$out"; fi
touch "$HOME/.bashrc"; "$root/install.sh" --prefix "$t/prefix" >/dev/null 2>&1; "$root/install.sh" --prefix "$t/prefix" >/dev/null 2>&1
n=$(grep -c '>>> claude-shim >>>' "$HOME/.bashrc"); [ "$n" = 1 ] && ok "install is idempotent (one rc block)" || bad "install is idempotent (one rc block)" "blocks: $n"
"$root/uninstall.sh" --prefix "$t/prefix" >/dev/null 2>&1
if [ ! -e "$t/prefix" ] && ! grep -q claude-shim "$HOME/.bashrc"; then ok "uninstall removes prefix and rc block"; else bad "uninstall removes prefix and rc block"; fi

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
