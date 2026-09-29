#!/bin/bash
# setup_claude_config.sh — v1
# Installe la configuration Claude Code (CLAUDE.md et skills) tenue dans un depot
# PRIVE, cloné avec le token GitHub lu dans Vault par le helper de setup_git.sh.
# Doit donc tourner APRES setup_git.sh.
#
# Ce depot-ci est public : il ne contient que la mecanique. Le contenu (qui decrit
# notamment Nubonyxia) reste dans le depot prive.
#
#   ~/.claude/CLAUDE.md       -> <clone>/CLAUDE.md
#   ~/.claude/skills/<skill>  -> <clone>/skills/<skill>
#
# Le clone vit hors de ~/work : il est refait a chaque nouveau service, donc
# toujours a jour. Toute modification faite dedans doit etre poussee aussitot.

set -u

USER_HOME="/home/onyxia"
CLAUDE_DIR="$USER_HOME/.claude"
CONFIG_DIR="$USER_HOME/.local/share/claude-onyxia-config"
HELPER="$USER_HOME/.local/bin/git-credential-vault"
CONFIG_REPO="${CLAUDE_CONFIG_REPO:-https://github.com/paquitopg/claude-onyxia-config.git}"

echo "[claude-config] Configuration en cours..."

if [ ! -x "$HELPER" ]; then
  echo "[claude-config] ERREUR : $HELPER absent (setup_git.sh doit tourner avant)."
  exit 0
fi

# -- 1. Cloner, ou mettre a jour si le clone existe deja ---------------------
mkdir -p "$(dirname "$CONFIG_DIR")"
if [ -d "$CONFIG_DIR/.git" ]; then
  if git -c credential.helper="$HELPER" -c safe.directory="$CONFIG_DIR" \
       -C "$CONFIG_DIR" pull --ff-only --quiet 2>&1; then
    echo "[claude-config] Depot mis a jour."
  else
    echo "[claude-config] ATTENTION : mise a jour impossible, version locale conservee."
  fi
else
  if git -c credential.helper="$HELPER" clone --quiet "$CONFIG_REPO" "$CONFIG_DIR" 2>&1; then
    echo "[claude-config] Depot clone dans $CONFIG_DIR"
  else
    echo "[claude-config] ECHEC du clonage (depot prive : cle GITHUB_TOKEN absente de Vault ?)."
    exit 0
  fi
fi

# -- 2. Liens dans ~/.claude -------------------------------------------------
# Un fichier ou dossier reel deja present n'est jamais ecrase : il est mis de cote
# HORS de ~/.claude/skills, sinon Claude Code chargerait la copie comme un second skill.
BACKUP_DIR="$CLAUDE_DIR/claude-config-backups"
relier() {
  local cible="$1" lien="$2"
  if [ -e "$lien" ] && [ ! -L "$lien" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$lien" "$BACKUP_DIR/$(basename "$lien").$(date +%Y%m%d%H%M%S)"
    echo "[claude-config] $lien existant mis de cote dans $BACKUP_DIR."
  fi
  ln -sfn "$cible" "$lien"
}

mkdir -p "$CLAUDE_DIR/skills"

if [ -f "$CONFIG_DIR/CLAUDE.md" ]; then
  relier "$CONFIG_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "[claude-config] CLAUDE.md relie."
fi

for skill in "$CONFIG_DIR"/skills/*/; do
  [ -f "$skill/SKILL.md" ] || continue
  nom="$(basename "$skill")"
  relier "${skill%/}" "$CLAUDE_DIR/skills/$nom"
  echo "[claude-config] Skill '$nom' relie."
done

# -- 3. Droits (le script tourne souvent en root) ----------------------------
if [ "$(id -u)" = "0" ]; then
  chown -R onyxia:onyxia "$CONFIG_DIR" "$CLAUDE_DIR" 2>/dev/null || true
  chown onyxia:onyxia "$USER_HOME/.local" "$USER_HOME/.local/share" 2>/dev/null || true
fi

echo "[claude-config] Termine."
