# Ctrl-R over the live zsh-histdb database (instead of this shell's
# in-memory history).  Requires zsh-histdb and fzf; otherwise we leave
# fzf's own Ctrl-R binding untouched.
#
# The query reads the *curated* histdb universe (the same one
# zsh-autosuggestions' histdb_fish_like strategy reads), so commands that
# histdb deliberately drops at insert time (ls, cd, top, htop, space-prefixed,
# histdb itself) are not searchable here.

if (( ${+functions[_histdb_query]} && ${+commands[sqlite3]} && ${+commands[fzf]} )); then

  _yt_histdb_fzf() {
    emulate -L zsh
    # NOTE: no `pipefail` here — _histdb_query returns 1 even on success
    # (its `[[ $? -ne 0 ]] && echo` compound), which would poison the
    # pipeline's exit status and make us drop a valid fzf selection.
    setopt extendedglob no_aliases no_glob no_sh_glob noglobsubst no_ksharrays 2>/dev/null

    # One line per distinct command, most recently run first.
    # Newlines inside a command are rewritten to \x01 on read (and reversed
    # on accept) so one record always equals one line; the DB itself is
    # never modified.
    local query='
      SELECT REPLACE(commands.argv, char(10), char(1))
      FROM history
      JOIN commands ON history.command_id = commands.id
      GROUP BY history.command_id
      ORDER BY MAX(history.start_time) DESC
      LIMIT 50000
    '

    local selected ret
    # Inline fzf's own __fzf_defaults instead of calling it: fzf < 0.53
    # (e.g. Debian's 0.44.1) doesn't define __fzf_defaults, so the call would
    # expand to "" and silently drop ${FZF_DEFAULT_OPTS-} — i.e. the
    # --color=... that yt-autotheme sets.  This keeps FZF_DEFAULT_OPTS and
    # FZF_DEFAULT_OPTS_FILE flowing through on every fzf version.
    selected="$(
      _histdb_query "$query" |
      FZF_DEFAULT_OPTS="$(
        builtin printf '%s\n' "--height ${FZF_TMUX_HEIGHT:-40%} --bind=ctrl-z:ignore"
        command cat "${FZF_DEFAULT_OPTS_FILE-}" 2>/dev/null
        builtin printf '%s\n' "${FZF_DEFAULT_OPTS-} --scheme=history --bind=ctrl-r:toggle-sort ${FZF_CTRL_R_OPTS-} --query=${(qqq)LBUFFER}"
      )" \
      FZF_DEFAULT_OPTS_FILE='' \
      $(__fzfcmd)
    )"
    ret=$?

    if (( ret == 0 )) && [[ -n "$selected" ]]; then
      BUFFER="${selected//$'\x01'/$'\n'}"
      CURSOR=${#BUFFER}
    fi

    zle reset-prompt
    return $ret
  }
  zle -N _yt_histdb_fzf

  bindkey -M emacs '^R' _yt_histdb_fzf
fi
