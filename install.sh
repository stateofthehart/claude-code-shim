#!/usr/bin/env bash
# Install the claude shim.
#
#   ./install.sh                 copy into ~/.local/share/claude-shim and add it to PATH in your shell rc
#   ./install.sh --link          symlink to this checkout instead of copying (for developing the shim)
#   ./install.sh --prefix DIR    install somewhere else (default ~/.local/share/claude-shim)
#   ./install.sh --no-rc         don't touch shell rc files; print the PATH line instead
#
# One-liner on a new machine:
#   git clone https://github.com/stateofthehart/claude-shim ~/.local/src/claude-shim && ~/.local/src/claude-shim/install.sh
#
# Re-running is safe: files are replaced and the rc block is rewritten in place.
set -euo pipefail

src=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
prefix=${CLAUDE_SHIM_PREFIX:-$HOME/.local/share/claude-shim}
mode=copy
rc=1

while [ $# -gt 0 ]; do
  case "$1" in
    --link) mode=link ;;
    --prefix) prefix=$2; shift ;;
    --no-rc) rc=0 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '  %s\n' "$*"; }

# Dependencies
missing=()
for dep in bash jq grep sed awk; do command -v "$dep" >/dev/null || missing+=("$dep"); done
[ ${#missing[@]} -eq 0 ] || { echo "install.sh: missing required tools: ${missing[*]}" >&2; exit 1; }
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "install.sh: warning: bash ${BASH_VERSION} is old; the shim needs bash 4+ on PATH (macOS: brew install bash)" >&2
fi
command -v claude >/dev/null || echo "install.sh: note: no claude on PATH yet; install Claude Code, the shim finds it at run time" >&2

echo "Installing claude shim to $prefix ($mode)"
mkdir -p "$prefix"
for item in bin libexec VERSION; do
  rm -rf "${prefix:?}/$item"
  if [ $mode = link ]; then ln -s "$src/$item" "$prefix/$item"; else cp -R "$src/$item" "$prefix/$item"; fi
done
chmod +x "$prefix/bin/claude" "$prefix/libexec/claude-search"
say "installed $(cat "$src/VERSION")"

bin=$prefix/bin
line="export PATH=\"$bin:\$PATH\""
begin='# >>> claude-shim >>>'
end='# <<< claude-shim <<<'

write_rc() {  # <file>
  local f=$1 tmp
  [ -e "$f" ] || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/claude-shim-rc.XXXXXX")
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
  {
    echo "$begin"
    echo "# Managed by claude-shim/install.sh. Keep this block last so the shim stays ahead of the real claude."
    echo "$line"
    echo "$end"
  } >> "$tmp"
  cat "$tmp" > "$f" && rm -f "$tmp"
  say "PATH set in $f"
}

if [ $rc = 1 ]; then
  wrote=0
  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do write_rc "$f" && wrote=1; done
  [ $wrote = 1 ] || { touch "$HOME/.bashrc"; write_rc "$HOME/.bashrc"; }
  say "open a new shell (or: source your rc) to pick it up"
else
  say "add this to your shell rc, after anything else that puts claude on PATH:"
  say "  $line"
fi

# Sanity check in a clean subshell with the new PATH
if PATH="$bin:$PATH" command -v claude >/dev/null && PATH="$bin:$PATH" claude shim >/dev/null 2>&1; then
  say "check: $(PATH="$bin:$PATH" claude shim)"
else
  say "check: shim installed; real claude not found yet"
fi
