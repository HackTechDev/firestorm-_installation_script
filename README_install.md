# Compiler et installer Firestorm sous Linux

Ce guide résume la procédure officielle (`doc/building_linux.md`) et l'automatise avec le script `install_firestorm.sh`.

> [!NOTE]
> L'équipe Firestorm n'assure aucun support pour les viewers compilés soi-même. Pour toute question, rejoindre le groupe [Firestorm Self Compilers](https://tinyurl.com/firestorm-self-compilers) dans Second Life.

## Prérequis

Cette installation a été réalisée sur **Lubuntu 26.04 LTS**. La procédure s'applique aussi aux autres variantes d'Ubuntu, car elles utilisent les mêmes paquets.

| | Recommandé (officiel) | Testé ici |
|---|---|---|
| Système | Ubuntu 22.04 LTS x86_64 | Lubuntu 26.04 LTS x86_64 |
| Compilateur | GCC 11 | GCC 15.2 |
| glibc | ≥ 2.34 | 2.43 |
| RAM | 16 Go ou plus | 7 Go + 12 Go de swap |
| Disque | 64 Go | — |
| CPU | 4 cœurs ou plus | 4 cœurs |

Seules les builds 64 bits sont possibles. Avec peu de RAM, réduisez le nombre de compilations en parallèle (`--jobs`) et ajoutez du swap (10 Go ou plus), sinon la compilation peut s'arrêter par manque de mémoire (`virtual memory exhausted`, `c++: fatal error`).

## Installation rapide

```bash
cd phoenix-firestorm
./install_firestorm.sh                          # compile ReleaseFS_open avec 3 jobs
./install_firestorm.sh --install ~/firestorm    # compile puis installe dans ~/firestorm
```

Le script :
1. installe les paquets apt manquants (demande le mot de passe `sudo`) ;
2. vérifie la RAM, le swap, l'espace disque et la version de GCC ;
3. crée un environnement Python `.venv` dans le dépôt et y installe `autobuild` (`requirements.txt`) ;
4. clone (ou met à jour) `fs-build-variables` à côté du dépôt ;
5. configure le build (Ninja, tests désactivés) ;
6. compile ;
7. avec `--install`, copie le viewer et crée le lanceur dans le menu des applications.

### Options

| Option | Effet |
|---|---|
| `--config <nom>` | Configuration autobuild (défaut `ReleaseFS_open`, voir ci-dessous) |
| `--jobs <n>` | Compilations en parallèle (défaut 3, environ 2 Go de RAM par job) |
| `--chan <nom>` | Nom du canal ; le viewer s'appellera `Firestorm-<nom>` |
| `--install <dossier>` | Copie le viewer compilé et crée le lanceur de menu |
| `--skip-deps` | Ne touche pas aux paquets système |
| `--skip-configure` | Recompile sans reconfigurer (après une modification du code) |
| `--clean` | Repart de zéro et re-télécharge les paquets tiers |

### Configurations disponibles sans licence

| Configuration | Contenu |
|---|---|
| `ReleaseFS_open` | Build standard, sans KDU ni FMOD |
| `RelWithDebInfoFS_open` | Idem, avec les symboles de débogage |
| `ReleaseOS` | Avec le support OpenSim |
| `RelWithDebInfoOS` | OpenSim, avec les symboles de débogage |

Les configurations `ReleaseFS*` sans `_open` demandent les bibliothèques propriétaires KDU et FMOD Studio. Pour FMOD, suivre la section « Create FMOD Studio package » de `doc/building_linux.md`.

## Procédure manuelle

```bash
# Paquets système
sudo apt install libgl1-mesa-dev libglu1-mesa-dev libpulse-dev build-essential python3-pip python3-venv \
     git libssl-dev libxinerama-dev libxrandr-dev libfontconfig-dev libfreetype-dev cmake ninja-build ccache

# Autobuild
cd phoenix-firestorm
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Variables de build
git clone https://github.com/FirestormViewer/fs-build-variables.git ../fs-build-variables
export AUTOBUILD_VARIABLES_FILE=$(realpath ../fs-build-variables/variables)

# Configuration puis compilation
ARGS="--ninja --jobs 3 --compiler-cache -DLL_TESTS:BOOL=FALSE -DGCC_DISABLE_FATAL_WARNINGS:BOOL=TRUE"
autobuild configure -A 64 -c ReleaseFS_open -- $ARGS
autobuild build -A 64 -c ReleaseFS_open --no-configure -- $ARGS
```

`-DGCC_DISABLE_FATAL_WARNINGS:BOOL=TRUE` n'est utile qu'avec un GCC plus récent que la version 11 (voir « Problèmes courants »). `--compiler-cache` utilise `ccache` pour accélérer les recompilations.

La première configuration télécharge les paquets tiers et prend plusieurs minutes. La compilation prend une à plusieurs heures selon la machine.

## Résultat

- Viewer prêt à lancer : `build-linux-x86_64/newview/packaged/firestorm`
- Archive distribuable : `build-linux-x86_64/newview/Phoenix*.tar.*`
- Journal de compilation : `build-linux-x86_64/logs/build_linux.log`

Pour installer le viewer ailleurs (ou sur une autre machine) :

```bash
rsync -rptgoDLK --update build-linux-x86_64/newview/packaged/ ~/firestorm/
cd ~/firestorm && etc/refresh_desktop_app_entry.sh   # lanceur dans le menu Internet/Réseau
./firestorm
```

## Problèmes courants

- **`error: array subscript ... is partly outside array bounds [-Werror=array-bounds=]`** : ce faux positif a été rencontré avec GCC 15 sur Lubuntu 26.04, dans `llpaneloutfitedit.cpp`. Le projet compile avec `-Werror`, si bien que les nouveaux avertissements des GCC récents bloquent le build. La solution est de reconfigurer avec `-DGCC_DISABLE_FATAL_WARNINGS:BOOL=TRUE`. Le script le fait automatiquement dès que GCC est plus récent que la version 11.

- **Manque de mémoire** : relancer avec un `--jobs` plus petit et `--skip-configure` ; ajouter du swap.
- **Erreurs SDL2 lors d'une reconfiguration** : supprimer les fichiers SDL2 déjà extraits, puis reconfigurer :
  ```bash
  rm -rf build-linux-x86_64/packages/include/SDL2/ build-linux-x86_64/packages/docs/SDL/
  rm -f build-linux-x86_64/packages/LICENSES/SDL.txt build-linux-x86_64/packages/lib/release/*SDL*
  ```
- **`autobuild.xml` modifié** (après `autobuild installables edit`) : le restaurer avant de récupérer de nouveaux commits (`git checkout autobuild.xml`).
- **Son retardé ou absent** : voir `README.Linux.txt` dans le dossier du viewer, ou compiler avec FMOD Studio.
