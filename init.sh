#!/bin/bash
# init.sh — orchestrateur d'initialisation SSPCloud
#
# C'est la SEULE URL à fournir à Onyxia (champ « script d'initialisation ») :
#   https://raw.githubusercontent.com/paquitopg/sspcloud-init-scripts/refs/heads/main/init.sh
#
# Chaque brique est téléchargée puis exécutée avec bash. Deux précautions :
#   - le fichier est enregistré avant d'être lancé, ce qui permet de vérifier
#     qu'il a bien été téléchargé (un « curl | bash » sur un téléchargement
#     échoué ne fait rien, sans rien dire) ;
#   - l'échec d'une brique est signalé mais n'interrompt pas les suivantes.

BASE_URL="https://raw.githubusercontent.com/paquitopg/sspcloud-init-scripts/main"
TRAVAIL="$(mktemp -d)"

echo "############ INIT SSPCLOUD : DÉBUT ############"
echo "utilisateur : $(id -un) (uid $(id -u))"

executer_brique() {
  local nom="$1" fichier="$TRAVAIL/$1"
  echo ""
  echo "---- $nom ----"

  if ! curl -fsSL --max-time 60 "$BASE_URL/$nom" -o "$fichier"; then
    echo "[init] ÉCHEC du téléchargement de $nom depuis $BASE_URL"
    echo "       Vérifie l'URL du dépôt et que le fichier y est bien poussé."
    return 1
  fi
  if [ ! -s "$fichier" ]; then
    echo "[init] $nom téléchargé mais vide — brique ignorée."
    return 1
  fi

  bash "$fichier"
  local code=$?
  if [ "$code" -ne 0 ]; then
    echo "[init] $nom s'est terminé avec le code $code."
  fi
  return "$code"
}

executer_brique "install_claude.sh"
executer_brique "setup_git.sh"

rm -rf "$TRAVAIL"
echo ""
echo "############ INIT SSPCLOUD : FIN ############"
