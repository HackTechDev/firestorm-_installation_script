#!/usr/bin/env bash
# Installation de l'environnement de build, compilation et installation de Firestorm (Linux x86_64).
# Voir README_install.md pour le détail des étapes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_URL="https://github.com/FirestormViewer/phoenix-firestorm.git"

# Sources du viewer : le dossier du script s'il s'agit d'un clone de phoenix-firestorm,
# sinon ../phoenix-firestorm (cloné s'il n'existe pas)
if [ -f "$SCRIPT_DIR/autobuild.xml" ]; then
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$(dirname "$SCRIPT_DIR")/phoenix-firestorm"
fi
BRANCH="master"

CONFIG="ReleaseFS_open"
JOBS=2
INSTALL_DIR=""
CHANNEL=""
SKIP_DEPS=0
SKIP_CONFIGURE=0
CLEAN=0

APT_PACKAGES=(
    libgl1-mesa-dev libglu1-mesa-dev libpulse-dev build-essential python3-pip python3-venv
    git libssl-dev libxinerama-dev libxrandr-dev libfontconfig-dev libfreetype-dev cmake ninja-build ccache
)

usage()
{
    cat <<EOF
Usage : $0 [options]

  --src <dossier>     Sources phoenix-firestorm (défaut : $REPO_DIR)
                      Cloné depuis GitHub si le dossier n'existe pas
  --branch <nom>      Branche à cloner (défaut : $BRANCH ; ignoré si les sources existent déjà)
  --config <nom>      Configuration autobuild (défaut : $CONFIG)
                      ReleaseFS_open | RelWithDebInfoFS_open | ReleaseOS | RelWithDebInfoOS
  --jobs <n>          Compilations en parallèle (défaut : $JOBS ; ~2 Go de RAM par job)
  --chan <nom>        Canal du viewer (nom final : Firestorm-<nom>)
  --install <dossier> Copie le viewer compilé dans <dossier> et crée le lanceur du menu
  --skip-deps         Ne pas vérifier/installer les paquets apt
  --skip-configure    Ne pas relancer l'étape de configuration (build incrémental)
  --clean             Supprime le build précédent et re-télécharge les paquets tiers
  -h, --help          Affiche cette aide
EOF
}

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --src)            REPO_DIR="$(realpath -m "$2")"; shift 2 ;;
        --branch)         BRANCH="$2"; shift 2 ;;
        --config)         CONFIG="$2"; shift 2 ;;
        --jobs)           JOBS="$2"; shift 2 ;;
        --chan)           CHANNEL="$2"; shift 2 ;;
        --install)        INSTALL_DIR="$2"; shift 2 ;;
        --skip-deps)      SKIP_DEPS=1; shift ;;
        --skip-configure) SKIP_CONFIGURE=1; shift ;;
        --clean)          CLEAN=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage; die "Option inconnue : $1" ;;
    esac
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs attend un entier positif (reçu : '$JOBS')."

VENV_DIR="$REPO_DIR/.venv"
VARIABLES_DIR="$(dirname "$REPO_DIR")/fs-build-variables"
BUILD_DIR="$REPO_DIR/build-linux-x86_64"

[ "$(uname -s)" = "Linux" ] || die "Ce script ne gère que Linux."
[ "$(uname -m)" = "x86_64" ] || die "Seule l'architecture x86_64 est supportée."

# --- 1. Paquets système ------------------------------------------------------
if [ "$SKIP_DEPS" -eq 0 ] && command -v dpkg >/dev/null; then
    log "Vérification des paquets système"
    missing=()
    for p in "${APT_PACKAGES[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Paquets manquants : ${missing[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    else
        echo "Tous les paquets sont présents."
    fi
fi

# --- 2. Sources du viewer ------------------------------------------------------
log "Sources du viewer ($REPO_DIR)"
if [ -f "$REPO_DIR/autobuild.xml" ]; then
    echo "Sources présentes, branche $(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo '?')."
elif [ -e "$REPO_DIR" ] && [ -n "$(ls -A "$REPO_DIR")" ]; then
    die "$REPO_DIR existe mais ne contient pas les sources phoenix-firestorm."
else
    echo "Clonage de $SOURCES_URL (branche $BRANCH)..."
    git clone --branch "$BRANCH" "$SOURCES_URL" "$REPO_DIR"
fi

# --- 3. Vérifications de la machine -------------------------------------------
log "Vérification de la machine"
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
swap_gb=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
free_gb=$(df -BG --output=avail "$REPO_DIR" | tail -1 | tr -dc '0-9')
gcc_major=$(gcc -dumpversion | cut -d. -f1)
echo "RAM : ${mem_gb} Go, swap : ${swap_gb} Go, disque libre : ${free_gb} Go, GCC : $(gcc -dumpversion)"
[ "$mem_gb" -lt 15 ] && warn "Moins de 16 Go de RAM : gardez --jobs bas et prévoyez du swap (10 Go ou plus)."
[ "$free_gb" -lt 40 ] && warn "Peu d'espace disque libre (64 Go recommandés)."
[ "$gcc_major" -ne 11 ] && warn "GCC $gcc_major détecté ; la référence officielle est GCC 11 (Ubuntu 22.04)."

# --- 4. Autobuild dans un venv Python ----------------------------------------
log "Installation d'autobuild dans $VENV_DIR"
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$REPO_DIR/requirements.txt"
AUTOBUILD="$VENV_DIR/bin/autobuild"
"$AUTOBUILD" --version
# viewer_manifest.py a besoin du module llsd installé dans le venv : CMake doit choisir ce Python
export PATH="$VENV_DIR/bin:$PATH"
export PYTHON="$VENV_DIR/bin/python3"
# Ne pas faire apparaître le venv dans git status
grep -qx '.venv/' "$REPO_DIR/.git/info/exclude" 2>/dev/null || echo '.venv/' >> "$REPO_DIR/.git/info/exclude"

# --- 5. Variables de build Firestorm -----------------------------------------
log "Variables de build ($VARIABLES_DIR)"
if [ -d "$VARIABLES_DIR/.git" ]; then
    git -C "$VARIABLES_DIR" pull -q --ff-only || warn "Impossible de mettre à jour fs-build-variables, version locale utilisée."
else
    git clone -q https://github.com/FirestormViewer/fs-build-variables.git "$VARIABLES_DIR"
fi
export AUTOBUILD_VARIABLES_FILE="$VARIABLES_DIR/variables"

# --- 6. Configuration ----------------------------------------------------------
cd "$REPO_DIR"
extra_args=(--ninja --jobs "$JOBS" -DLL_TESTS:BOOL=FALSE)
[ -n "$CHANNEL" ] && extra_args+=(--chan="$CHANNEL")
command -v ccache >/dev/null && extra_args+=(--compiler-cache)
# Les GCC récents (>= 12) lèvent des faux positifs (-Warray-bounds...) que -Werror rend bloquants
[ "$gcc_major" -gt 11 ] && extra_args+=(-DGCC_DISABLE_FATAL_WARNINGS:BOOL=TRUE)

if [ "$SKIP_CONFIGURE" -eq 0 ]; then
    log "Configuration ($CONFIG) - premier lancement long : téléchargement des paquets tiers"
    # Forcer aussi le Python du venv dans un cache CMake existant (sinon l'ancienne valeur est conservée)
    cfg_args=("${extra_args[@]}" "-DPYTHON_EXECUTABLE:FILEPATH=$PYTHON")
    [ "$CLEAN" -eq 1 ] && cfg_args+=(--clean)
    "$AUTOBUILD" configure -A 64 -c "$CONFIG" -- "${cfg_args[@]}"
fi

# --- 7. Compilation ------------------------------------------------------------
log "Compilation ($CONFIG, $JOBS jobs) - compter une à plusieurs heures"
"$AUTOBUILD" build -A 64 -c "$CONFIG" --no-configure -- "${extra_args[@]}"

PACKAGED_DIR="$BUILD_DIR/newview/packaged"
[ -x "$PACKAGED_DIR/firestorm" ] || die "Compilation terminée mais $PACKAGED_DIR/firestorm est introuvable."
log "Viewer compilé dans $PACKAGED_DIR"

# --- 8. Installation (optionnelle) --------------------------------------------
if [ -n "$INSTALL_DIR" ]; then
    log "Installation dans $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    rsync -rptgoDLK --update "$PACKAGED_DIR/" "$INSTALL_DIR/"
    if [ -x "$INSTALL_DIR/etc/refresh_desktop_app_entry.sh" ]; then
        (cd "$INSTALL_DIR" && etc/refresh_desktop_app_entry.sh) || warn "Création du lanceur de menu échouée."
    fi
    echo "Lancer avec : $INSTALL_DIR/firestorm"
else
    echo "Lancer avec : $PACKAGED_DIR/firestorm"
fi
