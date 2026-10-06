#!/bin/bash
# install_gh.sh — CLI GitHub (gh), en espace utilisateur
#
# L'archive officielle est dépliée dans ~/.local/share/gh : ni root ni apt,
# donc la même voie sur SSPCloud et sur Nubonyxia (GitHub y est joignable).
#
# Authentification : aucun « gh auth login », aucun token écrit sur le disque.
# ~/.local/bin/gh est un lanceur qui lit GITHUB_TOKEN dans Vault à chaque
# appel, avec le helper installé par setup_git.sh, puis passe la main au
# vrai binaire.

set -u

USER_HOME="/home/onyxia"
BIN_DIR="$USER_HOME/.local/bin"
GH_DIR="$USER_HOME/.local/share/gh"
LANCEUR="$BIN_DIR/gh"
BASHRC="$USER_HOME/.bashrc"

VERSION_SECOURS="2.102.0"         # si la dernière version ne peut pas être lue

echo "=== [gh] Installation ==="

case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "[gh] architecture non prévue : $(uname -m) — brique ignorée."; exit 0 ;;
esac

# -- 1. Dernière version -----------------------------------------------------
# Lue dans la redirection de /releases/latest : l'API GitHub, elle, est
# limitée à 60 appels par heure et par adresse IP sans token.
VERSION=$(curl -fsSI --max-time 15 https://github.com/cli/cli/releases/latest 2>/dev/null \
  | tr -d '\r' | sed -n 's#^[Ll]ocation: .*/tag/v##p')
if [ -z "${VERSION:-}" ]; then
  VERSION="$VERSION_SECOURS"
  echo "[gh] dernière version non déterminée, on prend $VERSION"
fi

if [ -x "$GH_DIR/bin/gh" ] \
   && "$GH_DIR/bin/gh" --version 2>/dev/null | grep -q "gh version $VERSION "; then
  echo "[gh] déjà présent en $VERSION"
else
  # -- 2. Archive, vérifiée par sa somme de contrôle -------------------------
  TRAVAIL="$(mktemp -d)"
  NOM="gh_${VERSION}_linux_${ARCH}.tar.gz"
  URL="https://github.com/cli/cli/releases/download/v${VERSION}"

  if curl -fsSL --max-time 180 "$URL/$NOM" -o "$TRAVAIL/$NOM" \
     && curl -fsSL --max-time 30 "$URL/gh_${VERSION}_checksums.txt" \
             -o "$TRAVAIL/sommes.txt"; then
    if (cd "$TRAVAIL" && grep " $NOM\$" sommes.txt | sha256sum -c --status); then
      rm -rf "$GH_DIR"; mkdir -p "$GH_DIR"
      tar -xzf "$TRAVAIL/$NOM" -C "$GH_DIR" --strip-components=1 \
        && echo "[gh] $VERSION déplié dans $GH_DIR" \
        || echo "[gh] ÉCHEC de l'extraction"
    else
      echo "[gh] ÉCHEC : somme de contrôle incorrecte pour $NOM — rien n'est installé."
    fi
  else
    echo "[gh] téléchargement impossible : $URL/$NOM"
  fi
  rm -rf "$TRAVAIL"
fi

if [ ! -x "$GH_DIR/bin/gh" ]; then
  echo "[gh] ÉCHEC : pas de binaire dans $GH_DIR/bin"
  exit 0        # on n'interrompt pas le reste de l'initialisation
fi

# -- 3. Lanceur : le token vient de Vault à chaque appel ---------------------
mkdir -p "$BIN_DIR"
cat > "$LANCEUR" << 'EOF'
#!/bin/bash
# Lanceur de gh, écrit par install_gh.sh. Le token GitHub est lu dans Vault
# (ou dans l'environnement) à chaque appel : il n'est jamais stocké.
if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
  GH_TOKEN="$("$HOME/.local/bin/git-credential-vault" secret GITHUB_TOKEN 2>/dev/null)"
  [ -n "$GH_TOKEN" ] && export GH_TOKEN
fi
exec "$HOME/.local/share/gh/bin/gh" "$@"
EOF
chmod +x "$LANCEUR"

# -- 4. PATH, droits, vérification -------------------------------------------
if ! grep -q '\.local/bin' "$BASHRC" 2>/dev/null; then
  {
    echo ''
    echo '# Outils en espace utilisateur (gh, helper git).'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
  } >> "$BASHRC"
  echo "[gh] PATH complété dans .bashrc"
fi

if [ "$(id -u)" = "0" ]; then
  chown -R onyxia:onyxia "$USER_HOME/.local" 2>/dev/null || true
  chown onyxia:onyxia "$BASHRC" 2>/dev/null || true
fi

echo "[gh] OK — $("$GH_DIR/bin/gh" --version 2>/dev/null | head -1)"
echo "[gh] Token : clé GITHUB_TOKEN de Vault, lue à chaque appel (gh auth status pour vérifier)."
echo "=== [gh] Fin ==="
