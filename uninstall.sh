#!/usr/bin/env bash
# Remove the claude shim: deletes the install prefix and the PATH block from ~/.bashrc / ~/.zshrc.
# Never touches Claude Code itself or anything under ~/.claude.
#
#   ./uninstall.sh [--prefix DIR]
set -euo pipefail

prefix=${CLAUDE_SHIM_PREFIX:-$HOME/.local/share/claude-shim}
case "${1:-}" in --prefix) prefix=$2 ;; -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

begin='# >>> claude-shim >>>'
end='# <<< claude-shim <<<'

for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -e "$f" ] && grep -qF "$begin" "$f" || continue
  tmp=$(mktemp "${TMPDIR:-/tmp}/claude-shim-rc.XXXXXX")
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
  cat "$tmp" > "$f" && rm -f "$tmp"
  echo "  removed PATH block from $f"
done

if [ -e "$prefix/bin/claude" ]; then
  rm -rf "${prefix:?}"
  echo "  removed $prefix"
else
  echo "  nothing installed at $prefix"
fi
echo "Open a new shell; claude now runs Claude Code directly."
