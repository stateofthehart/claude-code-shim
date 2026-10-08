# claude-shim

A thin wrapper around the [Claude Code](https://claude.com/claude-code) CLI that adds session management. Every command it doesn't handle is passed straight through to the real `claude`.

| Command | What it does |
|---|---|
| `claude rm [-y] [-n] <session>` | Delete a session (regular or background) and everything stored for it. |
| `claude mv [-n] <session> <dir>` | Move a session so it resumes from another directory. |
| `claude ls [-r] [options] [DIR]` | List sessions started in DIR (default: current directory), newest first. `-r` includes subdirectories. |
| `claude search [options] PATTERN...` | Search session transcripts by regex (`claude search -h`). |
| `claude shim` | Show the shim version and which real `claude` it wraps. |

`ls` and `search` show each session's directory, title, name, id, and whether it's `[running]` or `[background]` right now. `-p` adds the first prompt, `-L` the last exchange.

`<session>` can be a full session id, an id prefix (4+ characters), or a session name (`/rename` title or agent name). Session ids are global, so these commands work from any directory. `-n` is a dry run: it shows what would happen and changes nothing.

## Install

```sh
git clone https://github.com/stateofthehart/claude-code-shim ~/.local/src/claude-code-shim
~/.local/src/claude-code-shim/install.sh
```

Then open a new shell. `claude shim` confirms it's active.

The installer copies the shim into `~/.local/share/claude-shim` and adds a marked PATH block to the end of `~/.bashrc` and `~/.zshrc` (whichever exist). Re-running it upgrades in place.

| Option | Effect |
|---|---|
| `--link` | Symlink to the checkout instead of copying (for working on the shim). |
| `--prefix DIR` | Install somewhere other than `~/.local/share/claude-shim`. |
| `--no-rc` | Leave shell rc files alone and print the PATH line to add yourself. |

To update: `git -C ~/.local/src/claude-code-shim pull && ~/.local/src/claude-code-shim/install.sh`.
To remove: `~/.local/src/claude-code-shim/uninstall.sh` (never touches Claude Code or `~/.claude`).

**Requirements:** bash 4+, `jq`, and the usual `grep`/`sed`/`awk`. Works on Linux and macOS (on macOS, `brew install bash jq`).

The shim must come before the real `claude` on PATH, which is why the rc block goes at the end of the file. It finds the real binary by skipping itself on PATH; set `CLAUDE_SHIM_REAL=/path/to/claude` to pin it.

## What gets deleted or moved

Claude Code keeps a session's data in several places under `~/.claude` (or `$CLAUDE_CONFIG_DIR`):

| Path | Contents | `rm` | `mv` |
|---|---|---|---|
| `projects/<dir>/<id>.jsonl` | the transcript | deleted | moved |
| `projects/<dir>/<id>/` | subagent transcripts, tool results, title | deleted | moved |
| `file-history/<id>/` | file snapshots for undo | deleted | kept (global) |
| `session-env/<id>/` | session environment | deleted | kept (global) |
| `projects/<dir>/memory/` | auto-memory, **shared by every session in that directory** | kept | not carried over |

`<dir>` is the session's working directory with every non-alphanumeric character replaced by `-`.

## Safety

- `rm` shows the session (title, directory, last used, first prompt) and asks before deleting, unless `-y`.
- `rm` refuses a session that's open in a terminal. Background sessions go through Claude Code's own `claude rm` first, which stops them and removes their worktree when safe, then the shim deletes the remaining files.
- `mv` refuses running sessions and background sessions (Claude Code tracks background sessions by directory).
- Nothing is ever deleted outside the session's own paths.

## Caveats

- This depends on Claude Code's on-disk layout, which isn't a public API and may change between versions. Run `tests/run.sh` after upgrading Claude Code if anything looks off.
- `mv` doesn't rewrite the working directory recorded inside the transcript. Resuming from the new directory works by session id; tools in the resumed session use the directory you resume from.

## Development

```sh
tests/run.sh      # self-contained: fake ~/.claude and a stub claude; never touches real sessions
```

CI runs shellcheck and the tests on Linux and macOS.
