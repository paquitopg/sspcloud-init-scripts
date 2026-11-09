# sspcloud-init-scripts

Script d'initialisation pour les services VSCode Onyxia (SSPCloud, Nubonyxia).
URL à indiquer dans le champ « script d'initialisation » du service :

```
https://raw.githubusercontent.com/paquitopg/sspcloud-init-scripts/refs/heads/main/init.sh
```

`init.sh` télécharge et lance chaque brique ; l'échec de l'une n'arrête pas les suivantes.

| Brique | Rôle |
| --- | --- |
| `install_claude.sh` | Node.js 22, CLI Claude Code, extension VSCode, token `CLAUDE_CODE_OAUTH_TOKEN` lu dans Vault (pas de `claude login`) |
| `install_claude_plugins.sh` | bun, plugins Claude Code (compound-engineering, frontend-design, ponytail) |
| `install_openspec.sh` | CLI OpenSpec (télémétrie coupée) |
| `setup_git.sh` | Git, helper `git-credential-vault`, clone du dépôt du service |
| `install_gh.sh` | CLI GitHub, token lu dans Vault |
| `setup_claude_config.sh` | `CLAUDE.md` et skills depuis un dépôt privé |
| `setup_vscode.sh` | Thème « Dark Modern » par défaut (sans écraser un thème déjà choisi) |

Aucun secret ici : les tokens sont lus dans Vault à chaque usage.

## Alias git : GitHub ↔ Forge

`setup_git.sh` installe quatre alias quand un remote `forge` existe (Vault : `FORGE_HOST`,
`FORGE_TOKEN`, `FORGE_REMOTES`). La **Forge est la référence** (son `main` ne change que par
merge request) ; le `main` de GitHub n'en est que le miroir.

| Alias | Où | Effet |
| --- | --- | --- |
| `git forge-pull [main]` | Nubonyxia | Recopie `main` de la Forge vers GitHub, en avance rapide seulement |
| `git feat <nom>` | SSPCloud | Nouvelle branche partie de `origin/main` (le miroir) |
| `git ship <nom>` | Nubonyxia | Rebase la branche sur `forge/main`, la republie sur GitHub (`--force-with-lease`), puis `forge-push` |
| `git forge-push` | Nubonyxia | Envoie la branche courante à la Forge (refuse `main`) |

SSPCloud n'atteint pas la Forge : le VSCode Nubonyxia, qui voit la Forge et GitHub, sert de
passerelle.

### Exemple : une fonctionnalité

```bash
# 1. Nubonyxia : mettre le miroir GitHub à jour
git forge-pull

# 2. SSPCloud : coder avec Claude Code
git feat filtre-onglet4
claude                                   # coder, puis :
git add app/onglet4.R && git commit -m "Onglet 4 : ajouter le filtre par bureau"
git push -u origin HEAD

# 3. Nubonyxia : livrer à la Forge
git ship filtre-onglet4                  # puis merge request vers main sur la Forge

# 4. Nubonyxia, après la fusion (avance rapide) : miroir à jour, puis déploiement manuel
git forge-pull
```

Si le rebase de `git ship` rencontre un conflit, résoudre, `git rebase --continue`, puis relancer
`git ship`. Ne jamais pousser directement sur le `main` de la Forge ni fusionner à la main dans
celui de GitHub.
