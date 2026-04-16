# Ghostty shell integration wrapper. See ghostty-zdotdir-chain for details.
#
# Zsh resets HISTFILE to $ZDOTDIR/.zsh_history for interactive shells after
# .zshenv finishes. With ZDOTDIR pointing at our integration dir, history
# would land inside the app bundle. Fix it before sourcing the user's .zshrc
# so they can still override.
if [[ "${HISTFILE-}" = "${ZDOTDIR}/"* ]]; then
    'builtin' 'export' HISTFILE="${HOME}/.zsh_history"
fi
'builtin' 'source' '--' "${${(%):-%x}:A:h}/ghostty-zdotdir-chain" .zshrc
