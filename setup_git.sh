#!/bin/bash
# setup_git.sh — v4
# Configure Git pour toutes les forges, sans aucune donnee personnelle
# ni secret dans ce fichier, et clone automatiquement le depot du service.
#
# Sources des valeurs (par ordre de priorite) :
#   nom / email  : GIT_USER_NAME / GIT_USER_MAIL (fournis par Onyxia)
#                  sinon les cles GIT_NAME / GIT_EMAIL dans Vault
#   tokens       : lus dans Vault a la volee par le helper (jamais stockes)
#   depot        : GIT_REPOSITORY (fourni par Onyxia, onglet Git)

set -u

USER_HOME="/home/onyxia"
WORK_DIR="$USER_HOME/work"
GITCONFIG="$USER_HOME/.gitconfig"
BIN_DIR="$USER_HOME/.local/bin"
HELPER="$BIN_DIR/git-credential-vault"
BASHRC="$USER_HOME/.bashrc"

BASE_URL="https://raw.githubusercontent.com/paquitopg/sspcloud-init-scripts/main"

echo "[git] Configuration en cours..."

# -- 1. Installer le helper --------------------------------------------------
mkdir -p "$BIN_DIR"
if curl -fsSL "$BASE_URL/git-credential-vault" -o "$HELPER"; then
  chmod +x "$HELPER"
  echo "[git] Helper installe."
else
  echo "[git] ERREUR : telechargement du helper impossible."
  exit 0
fi

# -- 2. Identite : Onyxia d'abord, sinon Vault ------------------------------
# Aucune valeur en dur : on lit l'environnement, puis Vault en secours.
GIT_NAME_VALUE="${GIT_USER_NAME:-}"
GIT_MAIL_VALUE="${GIT_USER_MAIL:-}"

[ -z "$GIT_NAME_VALUE" ] && GIT_NAME_VALUE="$("$HELPER" secret GIT_NAME 2>/dev/null)"
[ -z "$GIT_MAIL_VALUE" ] && GIT_MAIL_VALUE="$("$HELPER" secret GIT_EMAIL 2>/dev/null)"

gitcfg() { git config --file "$GITCONFIG" "$@"; }

if [ -n "$GIT_NAME_VALUE" ]; then
  gitcfg user.name "$GIT_NAME_VALUE"
  echo "[git] user.name configure (depuis l'environnement ou Vault)."
else
  echo "[git] ATTENTION : nom introuvable (ni GIT_USER_NAME, ni cle GIT_NAME)."
fi

if [ -n "$GIT_MAIL_VALUE" ]; then
  gitcfg user.email "$GIT_MAIL_VALUE"
  echo "[git] user.email configure (depuis l'environnement ou Vault)."
else
  echo "[git] ATTENTION : email introuvable (ni GIT_USER_MAIL, ni cle GIT_EMAIL)."
fi

gitcfg init.defaultBranch main
gitcfg pull.rebase false

# -- 3. Un seul helper, routage automatique par forge -----------------------
gitcfg credential.helper "$HELPER"
git config --file "$GITCONFIG" --remove-section 'credential.https://github.com' 2>/dev/null || true
git config --file "$GITCONFIG" --remove-section 'credential.https://gitlab.com' 2>/dev/null || true
echo "[git] Helper unique configure (GitHub / GitLab automatiques)."

# -- 4. Neutraliser l'askpass de VSCode ------------------------------------
if ! grep -q "unset GIT_ASKPASS" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'EOF'

# --- Laisse agir les helpers git plutot que l'askpass de VSCode ---
unset GIT_ASKPASS
unset VSCODE_GIT_ASKPASS_NODE
unset VSCODE_GIT_ASKPASS_MAIN
unset VSCODE_GIT_ASKPASS_EXTRA_ARGS
unset VSCODE_GIT_IPC_HANDLE
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
EOF
  echo "[git] Askpass VSCode neutralise + PATH complete."
fi

# -- 5. Cloner automatiquement le depot du service -------------------------
# Onyxia fournit GIT_REPOSITORY (onglet Git). Son clone natif echoue pour un
# depot prive sans token ; on le refait ici avec le helper Vault.
if [ -n "${GIT_REPOSITORY:-}" ]; then
  REPO_NAME=$(basename "$GIT_REPOSITORY" .git)
  TARGET="$WORK_DIR/$REPO_NAME"
  mkdir -p "$WORK_DIR"

  if [ -d "$TARGET/.git" ]; then
    echo "[git] Depot deja present : $TARGET"
  else
    echo "[git] Clonage de $REPO_NAME..."
    BRANCH_OPT=""
    [ -n "${GIT_BRANCH:-}" ] && BRANCH_OPT="--branch ${GIT_BRANCH}"
    if git -c credential.helper="$HELPER" clone $BRANCH_OPT \
         "$GIT_REPOSITORY" "$TARGET" 2>&1; then
      echo "[git] Depot clone dans $TARGET"
    else
      echo "[git] ECHEC du clonage (token absent dans Vault ?)."
    fi
  fi
else
  echo "[git] Aucun GIT_REPOSITORY fourni : pas de clonage."
fi

# -- 6. Droits (le script tourne souvent en root) --------------------------
if [ "$(id -u)" = "0" ]; then
  chown -R onyxia:onyxia "$USER_HOME/.local" "$WORK_DIR" 2>/dev/null || true
  chown onyxia:onyxia "$GITCONFIG" "$BASHRC" 2>/dev/null || true
fi

echo "[git] Termine."
