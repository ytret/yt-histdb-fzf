# yt-histdb-fzf

Oh-My-Zsh plugin: `^R` opens an fzf picker over the **live zsh-histdb database**
instead of the current shell's in-memory history. Every tmux pane shares
`~/.histdb/zsh-history.db`, so it searches commands from *all* shells.

## Behavior
`_yt_histdb_fzf` (bound to `^R`, emacs mode) queries histdb for distinct
commands, most recent first, feeds them to fzf, and on accept inserts the
selection **without running it** — Enter again runs it (histdb records the new
execution). The fzf invocation mirrors fzf's own `fzf-history-widget`
(`__fzf_defaults` + `__fzfcmd`, `FZF_DEFAULT_OPTS`, `FZF_DEFAULT_OPTS_FILE`),
so `FZF_CTRL_R_OPTS` and `fzf-tmux` keep working.

## Load guard
Single file. Loaded after `fzf` (whose `^R` it overrides) and `zsh-histdb`.
The whole body sits behind a bind-time guard:
```zsh
if (( ${+functions[_histdb_query]} && ${+commands[sqlite3]} && ${+commands[fzf]} )); then
```
Missing deps → plugin is a no-op and fzf's shell-local `^R` stays. The widget
assumes its deps exist; no runtime fallback.

## SQL
```sql
SELECT REPLACE(commands.argv, char(10), char(1))
FROM history
JOIN commands ON history.command_id = commands.id
GROUP BY history.command_id
ORDER BY MAX(history.start_time) DESC
LIMIT 50000
```
- **Dedup by `argv` only** — one row per distinct command (not per host/dir).
- **Recency, not score** — fzf is the ranking engine; input is just
  "everything, newest first" (`histdb_fish_like` scoring is for suggestions).
- **No host/dir filter** — searches the entire DB.
- **`char(10) → char(1)` read-side only** — embedded newlines would split one
  command into two fzf records. Reversed on accept with
  `BUFFER="${selected//$'\x01'/$'\n'}"`. **DB is never modified.**

histdb drops `ls`, `cd`, `top`, `htop`, `histdb`, and space-prefixed commands
at insert time (`_BORING_COMMANDS` in `sqlite-history.zsh`), so they are not
searchable here — unlike the old fzf Ctrl-R over `$history`. Intentional: this
and autosuggestions then agree on what "history" means.

## Pitfalls (do not reintroduce)
1. **No `pipefail`.** `_histdb_query` returns 1 even on success — its last line
   `[[ "$?" -ne 0 ]] && echo ...` yields 1 when sqlite3 succeeds. With
   `pipefail` the pipeline reports 1 instead of fzf's 0, so a valid selection
   is dropped and the non-zero return rings the bell. Let fzf (last command)
   drive the status.
2. **`zle reset-prompt` + `return $ret` after fzf.** fzf's alternate screen
   clobbers the terminal; without these zsh never redraws the prompt/buffer
   (prompt disappears, typing from column 0, paste invisible). Mirrors fzf's
   own widget.

## Conventions
- `_yt-` prefix (matches `yt-key-bindings`); `emulate -L zsh` in the widget.
- One function, one widget, one `bindkey`; keep it a single file.
- `bindkey -M emacs '^R'` only — vi modes keep fzf's default.

## Lessons for agents
- **Test the pipeline, not the TUI.** fzf's TUI can't be driven reliably here.
  Stub `_histdb_query` (return 1, like the real one) and `fzf` (read one line,
  print it), then run the widget's exact command-substitution + `ret` logic in
  `zsh -c`. Assert on `ret` and `$selected`.
- **Add `timeout` to every test command.** Interactive `zsh -ic` without
  `</dev/null` hangs forever waiting for input.
- **`_histdb_query`'s success status is 1.** Re-check exit-status interaction
  whenever you re-pipe it.
- **Never change what's stored in the DB** — the newline rewrite stays in the
  `SELECT`; inserts belong to `zsh-histdb`.
- **`${(qqq)LBUFFER}`** safely quotes arbitrary buffer content for fzf's
  `--query=` (quotes, spaces, `$`, backslashes). Keep it.
