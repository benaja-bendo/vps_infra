#!/usr/bin/env bash
# =============================================================================
# setup-env.sh — Initialise l'environnement virtuel Python pour le projet Ansible
# =============================================================================
# Usage :
#   bash setup-env.sh          → crée le venv et installe tout
#   bash setup-env.sh --reset  → supprime et recrée le venv depuis zéro
# =============================================================================

set -euo pipefail

VENV_DIR="venv"
PYTHON_MIN="3.9"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Vérification de Python 3
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
  error "python3 introuvable. Installe Python >= ${PYTHON_MIN} et réessaie."
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Python détecté : ${PYTHON_VERSION}"

# Vérification version minimale
python3 -c "
import sys
major, minor = sys.version_info[:2]
if (major, minor) < (3, 9):
    print('Python >= 3.9 requis')
    sys.exit(1)
" || error "Python >= ${PYTHON_MIN} requis."

# ---------------------------------------------------------------------------
# 2. Option --reset : supprime l'ancien venv
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--reset" ]]; then
  warning "Option --reset détectée : suppression de l'ancien environnement..."
  rm -rf "${VENV_DIR}"
  info "Ancien environnement supprimé."
fi

# ---------------------------------------------------------------------------
# 3. Création du venv (si inexistant)
# ---------------------------------------------------------------------------
if [[ ! -d "${VENV_DIR}" ]]; then
  info "Création de l'environnement virtuel dans ./${VENV_DIR}/ ..."
  python3 -m venv "${VENV_DIR}"
  info "Environnement virtuel créé."
else
  info "Environnement virtuel déjà présent dans ./${VENV_DIR}/"
fi

# ---------------------------------------------------------------------------
# 4. Activation et mise à jour de pip
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"
info "Environnement activé."

info "Mise à jour de pip..."
pip install --quiet --upgrade pip

# ---------------------------------------------------------------------------
# 5. Installation des dépendances Python
# ---------------------------------------------------------------------------
info "Installation des dépendances Python (requirements.txt)..."
pip install --quiet -r requirements.txt
# certifi est requis pour corriger les accès SSL sur macOS (python.org)
pip install --quiet --upgrade certifi
info "Dépendances Python installées."

# ---------------------------------------------------------------------------
# 6. Installation des collections Ansible Galaxy
# ---------------------------------------------------------------------------
info "Installation des collections Ansible Galaxy (requirements.yml)..."
# macOS fix : Python from python.org doesn't use system certs — use certifi bundle
SSL_CERT_FILE=$(python3 -c "import certifi; print(certifi.where())")
export SSL_CERT_FILE
ansible-galaxy collection install -r requirements.yml --force
info "Collections Galaxy installées."

# ---------------------------------------------------------------------------
# 7. Résumé
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN} Environnement prêt !${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo "  Ansible  : $(ansible --version | head -n1)"
echo "  Python   : $(python3 --version)"
echo ""
echo "  Pour activer l'environnement manuellement :"
echo -e "  ${YELLOW}source ${VENV_DIR}/bin/activate${NC}"
echo ""
echo "  Pour lancer le playbook :"
echo -e "  ${YELLOW}ansible-playbook playbook.yml${NC}"
echo ""
