# Public, portable zsh configuration. Put machine-specific values in ~/.zshrc.local.

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi

typeset -U path PATH fpath FPATH
export PATH="$HOME/.local/bin:$PATH"

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
plugins=(git sudo macos fzf colored-man-pages docker kubectl npm yarn)
[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  [[ -r "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [[ -r "$HOMEBREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh" ]] && \
    source "$HOMEBREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh"
fi

(( $+functions[history-substring-search-up] )) && bindkey '^[[A' history-substring-search-up
(( $+functions[history-substring-search-down] )) && bindkey '^[[B' history-substring-search-down

(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"
(( $+commands[starship] )) && eval "$(starship init zsh)"

alias cat='bat'
alias ls='eza --icons --group-directories-first'
alias ll='eza -lh --icons --group-directories-first --git'
alias la='eza -a --icons --group-directories-first'
alias lla='eza -lah --icons --group-directories-first --git'
alias lt='eza --tree --icons --level=2'
alias k='kubectl'
alias python='python3'

[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Keep this last so it can highlight widgets loaded above and in ~/.zshrc.local.
[[ -n "${HOMEBREW_PREFIX:-}" && -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
