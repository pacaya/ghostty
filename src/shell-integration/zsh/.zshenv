# Based on (started as) a copy of Kitty's zsh integration. Kitty is
# distributed under GPLv3, so this file is also distributed under GPLv3.
# The license header is reproduced below:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script is sourced automatically by zsh when ZDOTDIR is set to this
# directory. It therefore assumes it's running within our shell integration
# environment and should not be sourced manually (unlike ghostty-integration).
#
# Ghostty keeps ZDOTDIR pointed at this directory for the lifetime of the
# shell and every descendant process, so that every zsh — the shell Ghostty
# spawns directly, tmux panes, subshells, `exec zsh`, `sudo -E zsh`,
# `zsh -c '…'` — re-enters this file and re-runs ghostty-integration. The
# user's rc files are chain-sourced from their original ZDOTDIR (preserved
# in GHOSTTY_ZSH_ZDOTDIR) via sibling wrappers: .zshrc, .zprofile, .zlogin,
# .zlogout.
#
# This file can get sourced with aliases enabled. To avoid alias expansion
# we quote everything that can be quoted. Some aliases will still break us
# though.

# Use try-always so ZDOTDIR is always restored to our dir, even if the
# user's .zshenv errors out.
{
    # Expose the user's ZDOTDIR while their .zshenv runs, so any
    # introspection of ZDOTDIR in that file sees the original value.
    # GHOSTTY_ZSH_ZDOTDIR is set by Ghostty's Zig side only when the user
    # had ZDOTDIR in their environment; if unset, the user's effective
    # ZDOTDIR defaults to $HOME per zsh semantics.
    if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
        'builtin' 'export' ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
    else
        'builtin' 'unset' 'ZDOTDIR'
    fi

    # Zsh treats unset ZDOTDIR as if it was HOME. We do the same.
    #
    # Source the user's .zshenv before sourcing ghostty-integration because
    # the former might set fpath and other things without which
    # ghostty-integration won't work.
    #
    # Use typeset in case we are in a function with warn_create_global in
    # effect. Unlikely but better safe than sorry.
    'builtin' 'typeset' _ghostty_file=${ZDOTDIR-$HOME}"/.zshenv"
    # Zsh ignores unreadable rc files. We do the same.
    # Zsh ignores rc files that are directories, and so does source.
    [[ ! -r "$_ghostty_file" ]] || 'builtin' 'source' '--' "$_ghostty_file"
} always {
    # Put ZDOTDIR back to our integration dir so zsh's subsequent
    # $ZDOTDIR/.zprofile, $ZDOTDIR/.zshrc, $ZDOTDIR/.zlogin lookups land on
    # our wrapper files. ${(%):-%x} is the path of this file; :A:h gives
    # its directory.
    'builtin' 'export' ZDOTDIR="${${(%):-%x}:A:h}"

    # Zsh defaults HISTFILE to $ZDOTDIR/.zsh_history, but may not apply
    # that default until after startup files. With ZDOTDIR pointing at
    # our integration dir, history would land inside the app bundle and
    # be lost on updates. Set a safe default if HISTFILE is unset or
    # already points into our dir. The user's .zshrc can still override.
    if [[ -z "${HISTFILE+set}" || "${HISTFILE-}" = "${ZDOTDIR}/"* ]]; then
        'builtin' 'export' HISTFILE="${HOME}/.zsh_history"
    fi

    if [[ -o 'interactive' ]]; then
        _ghostty_file="${ZDOTDIR}/ghostty-integration"
        if [[ -r "$_ghostty_file" ]]; then
            'builtin' 'autoload' '-Uz' '--' "$_ghostty_file"
            "${_ghostty_file:t}"
            'builtin' 'unfunction' '--' "${_ghostty_file:t}"
        fi
    fi
    'builtin' 'unset' '_ghostty_file'
}
