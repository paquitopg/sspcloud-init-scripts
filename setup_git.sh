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

# Synchronisation GitHub (origin) <-> forge interne (forge).
# Sur la forge, main n'evolue que par merge request :
#   git forge-push          envoie la branche de travail courante sur la forge
#                           (apres l'avoir mise a jour depuis GitHub) ; refuse main
#   git forge-pull [main]   recopie main de la forge vers GitHub (avance rapide
#                           uniquement : rien n'est jamais ecrase)
gitcfg alias.forge-push '!f() { b=$(git branch --show-current); case "$b" in ""|main|master) echo "forge-push : place-toi sur une branche de travail (pas \"$b\") ; main ne change sur la forge que par merge request." >&2; return 1;; esac; if git ls-remote --exit-code --heads origin "$b" >/dev/null; then git fetch origin "$b" && git merge --ff-only "origin/$b" || return 1; fi; git push -u forge "$b"; }; f'
gitcfg alias.forge-pull '!f() { m="${1:-main}"; git fetch forge "$m" && git push origin "refs/remotes/forge/$m:refs/heads/$m" || return 1; if [ "$(git branch --show-current)" = "$m" ]; then git merge --ff-only "forge/$m"; fi; }; f'

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
  
  # -- 5b. Remote « forge » : miroir du depot sur la forge interne ---------
  # Ni l'hote ni le chemin ne sont ecrits ici (depot public) : l'hote vient
  # de la cle FORGE_HOST, et la cle FORGE_REMOTES associe le nom du depot a
  # son chemin sur la forge, paires separees par des espaces :
  #   mon-depot=groupe/sous-groupe/mon-depot autre-depot=groupe/autre
  if [ -d "$TARGET/.git" ]; then
    FORGE_HOST_VALUE="$("$HELPER" secret FORGE_HOST 2>/dev/null)"
    FORGE_REMOTES_VALUE="$("$HELPER" secret FORGE_REMOTES 2>/dev/null)"
    FORGE_PATH=""
    for paire in $FORGE_REMOTES_VALUE; do
      [ "${paire%%=*}" = "$REPO_NAME" ] && FORGE_PATH="${paire#*=}"
    done
    if [ -n "$FORGE_HOST_VALUE" ] && [ -n "$FORGE_PATH" ]; then
      git -C "$TARGET" remote remove forge 2>/dev/null || true
      git -C "$TARGET" remote add forge "https://$FORGE_HOST_VALUE/${FORGE_PATH%.git}.git"
      echo "[git] Remote 'forge' ajoute : git forge-push (branche -> forge), git forge-pull (main forge -> GitHub)."
    else
      echo "[git] Pas de remote 'forge' pour $REPO_NAME (FORGE_HOST ou FORGE_REMOTES absent)."
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
