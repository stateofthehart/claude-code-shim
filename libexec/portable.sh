# shellcheck shell=bash
# Helpers that behave the same on GNU (Linux) and BSD (macOS) userlands. Sourced, not executed.

# Absolute path with symlinks resolved (readlink -f isn't on older macOS).
realpath_() {
  local p=$1 d
  while [ -L "$p" ]; do
    d=$(cd -P "$(dirname "$p")" && pwd)
    p=$(readlink "$p")
    case "$p" in /*) ;; *) p=$d/$p ;; esac
  done
  d=$(cd -P "$(dirname "$p")" && pwd)
  echo "$d/$(basename "$p")"
}

# File modification time as epoch seconds.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# Format epoch seconds: fmt_epoch <epoch> <strftime format>
fmt_epoch() { date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2"; }
