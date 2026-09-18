#!/bin/bash
# install_claude.sh — v5 : Node.js, CLI Claude Code, extension VSCode
#
# Reprend la procédure manuelle qui fonctionne, avec deux corrections :
#
#   - NodeSource en **22.x** et non 20.x : Claude Code exige Node >= 22
#     (sinon « npm WARN EBADENGINE » et un fonctionnement incertain) ;
#   - on installe le paquet « nodejs » SEUL. Il embarque npm. Ajouter le paquet
#     « npm » de Debian tirerait deux cents dépendances système (eslint,
#     webpack, babel…) dont on n'a aucun besoin.
#
# Une seconde voie, sans aucun droit administrateur, prend le relais si
# NodeSource échoue : l'archive officielle dépliée dans ~/.local/node.
#
# L'authentification reste manuelle : lancer « claude login » dans le terminal.

set -u

USER_HOME="/home/onyxia"
NPM_PREFIX="$USER_HOME/.npm-global"
NODE_LOCAL="$USER_HOME/.local/node"
BASHRC="$USER_HOME/.bashrc"

MAJEUR_REQUIS=22                  # exigé par @anthropic-ai/claude-code
VERSION_SECOURS="v22.11.0"        # si la version LTS ne peut pas être lue

echo "=== [Claude Code] Installation ==="
echo "[contexte] utilisateur : $(id -un) (uid $(id -u))"

SUDO=""
if [ "$(id -u)" != "0" ]; then
  sudo -n true 2>/dev/null && SUDO="sudo -n"
fi

export PATH="$NODE_LOCAL/bin:$NPM_PREFIX/bin:$PATH"

version_majeure() {
  command -v node >/dev/null 2>&1 || return 1
  node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1
}
node_ok() {
  local m; m=$(version_majeure) || return 1
  [ -n "$m" ] && [ "$m" -ge "$MAJEUR_REQUIS" ] 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Node.js
# ---------------------------------------------------------------------------
echo ""
if node_ok; then
  echo "[Node] déjà présent et suffisant : $(node --version)"
else
  presente=$(version_majeure || echo "")
  [ -n "$presente" ] && echo "[Node] présent en v$presente — trop ancien " \
                             "(>= $MAJEUR_REQUIS requis)"

  echo "[Node] Voie 1/2 : dépôt NodeSource ${MAJEUR_REQUIS}.x"
  if [ -n "$SUDO" ] || [ "$(id -u)" = "0" ]; then
    if curl -fsSL "https://deb.nodesource.com/setup_${MAJEUR_REQUIS}.x" \
            -o /tmp/nodesource.sh; then
      # « nodejs » seul : il embarque npm.
      $SUDO bash /tmp/nodesource.sh \
        && $SUDO apt-get install -y nodejs \
        || echo "  (NodeSource a échoué)"
      rm -f /tmp/nodesource.sh
    else
      echo "  téléchargement du dépôt impossible (réseau filtré ?)"
    fi
  else
    echo "  ignorée : ni root ni sudo"
  fi

  # -- Voie 2 : archive officielle, sans droits administrateur --------------
  if ! node_ok; then
    echo ""
    echo "[Node] Voie 2/2 : archive officielle, en espace utilisateur"

    VERSION=$(curl -fsS --max-time 15 https://nodejs.org/dist/index.json 2>/dev/null \
      | python3 -c "
import json, sys
try:
    versions = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for v in versions:                    # trié du plus récent au plus ancien
    if v.get('lts') and int(v['version'].lstrip('v').split('.')[0]) >= $MAJEUR_REQUIS:
        print(v['version']); break
" 2>/dev/null)

    if [ -z "${VERSION:-}" ]; then
      VERSION="$VERSION_SECOURS"
      echo "  version LTS non déterminée, on prend $VERSION"
    else
      echo "  dernière version LTS : $VERSION"
    fi

    ARCHIVE="/tmp/node-${VERSION}.tar.xz"
    URL="https://nodejs.org/dist/${VERSION}/node-${VERSION}-linux-x64.tar.xz"
    if curl -fsSL --max-time 180 "$URL" -o "$ARCHIVE"; then
      rm -rf "$NODE_LOCAL"; mkdir -p "$NODE_LOCAL"
      tar -xJf "$ARCHIVE" -C "$NODE_LOCAL" --strip-components=1 \
        && echo "  déplié dans $NODE_LOCAL" \
        || echo "  ÉCHEC de l'extraction"
      rm -f "$ARCHIVE"
    else
      echo "  téléchargement impossible : $URL"
    fi
  fi
fi

if ! node_ok; then
  echo ""
  echo "[Node] ÉCHEC : aucune version >= $MAJEUR_REQUIS disponible."
  echo "       version en place : $(version_majeure || echo aucune)"
  echo "       Lance « bash diag_node.sh » pour voir ce que le pod peut joindre."
  exit 0        # on n'interrompt pas le reste de l'initialisation
fi
echo ""
echo "[Node] $(node --version) — npm $(npm --version) — $(command -v node)"

# ---------------------------------------------------------------------------
# 2. npm en espace utilisateur, puis le CLI
# ---------------------------------------------------------------------------
echo ""
echo "[Claude Code] Installation de @anthropic-ai/claude-code..."
mkdir -p "$NPM_PREFIX"

if [ "$(id -u)" = "0" ]; then
  # Sous l'identité onyxia : sinon les fichiers appartiendraient à root et
  # l'utilisatrice ne pourrait plus les mettre à jour.
  chown -R onyxia:onyxia "$NPM_PREFIX" 2>/dev/null || true
  [ -d "$NODE_LOCAL" ] && chown -R onyxia:onyxia "$NODE_LOCAL" 2>/dev/null || true
  su onyxia -s /bin/bash -c \
    "export PATH='$NODE_LOCAL/bin:$NPM_PREFIX/bin:\$PATH'; \
     npm config set prefix '$NPM_PREFIX' && \
     npm install -g @anthropic-ai/claude-code" \
    || echo "  (installation du CLI en échec)"
else
  npm config set prefix "$NPM_PREFIX" \
    && npm install -g @anthropic-ai/claude-code \
    || echo "  (installation du CLI en échec)"
fi

# ---------------------------------------------------------------------------
# 3. Extension VSCode
# ---------------------------------------------------------------------------
echo ""
if command -v code-server >/dev/null 2>&1; then
  echo "[VSCode] Installation de l'extension anthropic.claude-code..."
  if [ "$(id -u)" = "0" ]; then
    su onyxia -s /bin/bash -c \
      "code-server --install-extension anthropic.claude-code" \
      || echo "  (extension non installée)"
  else
    code-server --install-extension anthropic.claude-code \
      || echo "  (extension non installée)"
  fi
else
  echo "[VSCode] code-server absent : extension ignorée"
fi

# ---------------------------------------------------------------------------
# 4. PATH persistant, droits, vérification
# ---------------------------------------------------------------------------
if ! grep -q '.npm-global/bin' "$BASHRC" 2>/dev/null; then
  {
    echo ''
    echo '# Node et Claude Code en espace utilisateur.'
    echo '# Placés AVANT le PATH système, pour primer sur un Node plus ancien.'
    echo 'export PATH="$HOME/.local/node/bin:$HOME/.npm-global/bin:$PATH"'
  } >> "$BASHRC"
  echo ""
  echo "[PATH] complété dans .bashrc"
fi

mkdir -p "$USER_HOME/.claude"
if [ "$(id -u)" = "0" ]; then
  chown -R onyxia:onyxia "$USER_HOME/.claude" "$NPM_PREFIX" "$BASHRC" \
    2>/dev/null || true
  [ -d "$NODE_LOCAL" ] && chown -R onyxia:onyxia "$NODE_LOCAL" 2>/dev/null || true
fi

echo ""
if [ -x "$NPM_PREFIX/bin/claude" ]; then
  echo "[Claude Code] OK — $("$NPM_PREFIX/bin/claude" --version 2>/dev/null \
        || echo 'installé')"
  echo "[Claude Code] Node utilisé : $(node --version)"
  echo "[Claude Code] Ouvre un NOUVEAU terminal (pour recharger le PATH),"
  echo "              puis : claude login"
else
  echo "[Claude Code] ÉCHEC : rien dans $NPM_PREFIX/bin"
fi
echo "=== [Claude Code] Fin ==="
