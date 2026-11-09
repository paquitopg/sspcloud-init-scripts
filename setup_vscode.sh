#!/bin/bash
# setup_vscode.sh — thème « Dark Modern » par défaut dans le VSCode du service.
# N'écrase pas un thème déjà choisi ; le fichier peut contenir des commentaires (JSONC),
# donc insertion textuelle plutôt que réécriture JSON.

SETTINGS="${HOME}/.local/share/code-server/User/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

if grep -q '"workbench.colorTheme"' "$SETTINGS" 2>/dev/null; then
  echo "[vscode] thème déjà défini, inchangé."
elif [ ! -s "$SETTINGS" ]; then
  printf '{\n  "workbench.colorTheme": "Dark Modern"\n}\n' > "$SETTINGS"
  echo "[vscode] thème Dark Modern défini."
else
  sed -i '0,/{/s//{\n  "workbench.colorTheme": "Dark Modern",/' "$SETTINGS"
  echo "[vscode] thème Dark Modern défini."
fi
