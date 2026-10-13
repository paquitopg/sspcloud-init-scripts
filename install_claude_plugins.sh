#!/bin/bash
# install_claude_plugins.sh — v1
# Installe les plugins Claude Code. ~/.claude n'est pas persistant : sans cette
# brique, chaque nouveau service démarre sans eux.
# Doit tourner APRES install_claude.sh (il faut le CLI « claude »).
#
# Les marketplaces sont des dépôts GitHub publics : pas besoin de token, ni
# d'être connecté à Claude. Sans accès à internet (Nubonyxia), la brique échoue
# sans rien casser.
#
# Pour ajouter un plugin : une ligne « <depot GitHub du marketplace> <plugin>@<marketplace> ».

set -u

USER_HOME="/home/onyxia"
NPM_PREFIX="$USER_HOME/.npm-global"
NODE_LOCAL="$USER_HOME/.local/node"

PLUGINS="
EveryInc/compound-engineering-plugin compound-engineering@compound-engineering-plugin
"

echo "[claude-plugins] Installation en cours..."

# Sous l'identité onyxia : sinon ~/.claude/plugins appartiendrait à root.
claude_onyxia() {
  if [ "$(id -u)" = "0" ]; then
    su onyxia -s /bin/bash -c \
      "export HOME='$USER_HOME' PATH='$NODE_LOCAL/bin:$NPM_PREFIX/bin:\$PATH'; claude $*"
  else
    PATH="$NODE_LOCAL/bin:$NPM_PREFIX/bin:$PATH" claude "$@"
  fi
}

if [ ! -x "$NPM_PREFIX/bin/claude" ]; then
  echo "[claude-plugins] ERREUR : CLI claude absent (install_claude.sh doit tourner avant)."
  exit 0
fi

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$USER_HOME/.claude"
  chown -R onyxia:onyxia "$USER_HOME/.claude" 2>/dev/null || true
fi

installes="$(claude_onyxia plugin list 2>/dev/null)"

echo "$PLUGINS" | while read -r depot plugin; do
  [ -n "$depot" ] || continue
  marketplace="${plugin#*@}"

  if echo "$installes" | grep -qF "$plugin"; then
    echo "[claude-plugins] $plugin déjà installé."
    continue
  fi

  if ! claude_onyxia plugin marketplace list 2>/dev/null | grep -qF "$marketplace"; then
    if ! claude_onyxia plugin marketplace add "$depot" >/dev/null 2>&1; then
      echo "[claude-plugins] ECHEC : marketplace $depot injoignable (pas d'internet ?)."
      continue
    fi
  fi

  if claude_onyxia plugin install "$plugin" --scope user >/dev/null 2>&1; then
    echo "[claude-plugins] $plugin installé."
  else
    echo "[claude-plugins] ECHEC de l'installation de $plugin."
  fi
done

echo "[claude-plugins] Terminé."
