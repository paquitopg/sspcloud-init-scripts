#!/bin/bash
# install_openspec.sh — CLI OpenSpec (@fission-ai/openspec)
# https://github.com/Fission-AI/OpenSpec
#
# Installe le CLI « openspec » dans ~/.npm-global, comme Claude Code : il n'est
# pas persistant et doit être réinstallé à chaque nouveau service.
# Doit tourner APRES install_claude.sh (il faut Node >= 20.19 et npm).
#
# Rien n'est initialisé ici : « openspec init » se lance une fois par projet,
# dans /home/onyxia/work, et ce qu'il écrit (openspec/, .claude/commands/…)
# vit dans le dépôt du projet, donc persiste.
#
# La télémétrie d'OpenSpec, active par défaut, est coupée dans .bashrc.

set -u

USER_HOME="/home/onyxia"
NPM_PREFIX="$USER_HOME/.npm-global"
NODE_LOCAL="$USER_HOME/.local/node"
BASHRC="$USER_HOME/.bashrc"

PAQUET="@fission-ai/openspec"

echo "=== [OpenSpec] Installation ==="

# Sous l'identité onyxia : sinon ~/.npm-global appartiendrait à root.
en_onyxia() {
  if [ "$(id -u)" = "0" ]; then
    su onyxia -s /bin/bash -c \
      "export HOME='$USER_HOME' PATH='$NODE_LOCAL/bin:$NPM_PREFIX/bin:\$PATH'; $*"
  else
    PATH="$NODE_LOCAL/bin:$NPM_PREFIX/bin:$PATH" "$@"
  fi
}

if ! en_onyxia npm --version >/dev/null 2>&1; then
  echo "[OpenSpec] ERREUR : npm absent (install_claude.sh doit tourner avant)."
  exit 0        # on n'interrompt pas le reste de l'initialisation
fi

if en_onyxia npm install -g "$PAQUET@latest" >/dev/null 2>&1; then
  echo "[OpenSpec] OK — $(en_onyxia openspec --version 2>/dev/null || echo 'installé')"
else
  echo "[OpenSpec] ÉCHEC de l'installation de $PAQUET (registre npm injoignable ?)."
  exit 0
fi

if ! grep -q 'OPENSPEC_TELEMETRY' "$BASHRC" 2>/dev/null; then
  {
    echo ''
    echo '# OpenSpec : pas de télémétrie.'
    echo 'export OPENSPEC_TELEMETRY=0'
  } >> "$BASHRC"
  [ "$(id -u)" = "0" ] && chown onyxia:onyxia "$BASHRC" 2>/dev/null
  echo "[OpenSpec] télémétrie coupée dans .bashrc"
fi

echo "[OpenSpec] Dans un projet : openspec init, puis /opsx:propose dans Claude Code."
echo "=== [OpenSpec] Fin ==="
