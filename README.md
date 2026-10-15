# sspcloud-init-scripts

Script d'initialisation pour les services VSCode Onyxia (SSPCloud, Nubonyxia).
URL à indiquer dans le champ « script d'initialisation » du service :

```
https://raw.githubusercontent.com/paquitopg/sspcloud-init-scripts/refs/heads/main/init.sh
```

`init.sh` télécharge et lance chaque brique ; l'échec de l'une n'arrête pas les suivantes.

| Brique | Rôle |
| --- | --- |
| `install_claude.sh` | Node.js 22, CLI Claude Code, extension VSCode |
| `install_claude_plugins.sh` | bun, plugins Claude Code (compound-engineering, frontend-design, ponytail) |
| `install_openspec.sh` | CLI OpenSpec (télémétrie coupée) |
| `setup_git.sh` | Git, helper `git-credential-vault`, clone du dépôt du service |
| `install_gh.sh` | CLI GitHub, token lu dans Vault |
| `setup_claude_config.sh` | `CLAUDE.md` et skills depuis un dépôt privé |

Aucun secret ici : les tokens sont lus dans Vault à chaque usage.
