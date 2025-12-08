#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Setting up project environments.
# created: 2025-06-04 Wed 09:20:29 BST
# updated: 2025-06-16 Mon 12:19:55 BST
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

################################################################################
## Environment setup ###########################################################
################################################################################

# set -euo pipefail
set -o ignoreeof
shopt -s expand_aliases
alias logger_info='logger -t "INFO [$(basename $0):$LINENO)]" -s'

export PATH_BASE=$([ -z "${PS1}" ] && echo $(dirname $0) || echo code)
logger_info "Using base path: ${PATH_BASE}"
SOURCE_FILES=(
  "${PATH_BASE}/logger.sh" # logger_info
  "${PATH_BASE}/utils.sh" # PKG_MAN, file_sync, path_project
  "${PATH_BASE}/utils_setup.sh" # setup_envs_*
  "${HOME}/.conda/init.sh"
)

for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  logger_info "Sourcing '${SOURCE_FILE}'"
  source ${SOURCE_FILE} || {
    echo "File does not exists." >&2
    exit 1
  }
  file_sync "${SOURCE_FILE}" # update project's
  file_sync "${HOME}/${SOURCE_FILE}" "${SOURCE_FILE}" # update original
done

shopt -u expand_aliases

################################################################################
# Global configuration #########################################################
################################################################################

PATH_PROJECT="$(path_project)"
declare -A  GIT_REPOS=(
  ['env_r']="envs/env_r.yaml"
  ['scqooc']="git@github.com:cramsuig/scqooc.git"
  ['celltypist']="git@github.com:cramsuig/sc2sp_benchmark.git"
  ['scanpy']="git@github.com:HCA-integration/scAtlasTb.git"
  ['rapids_singlecell']="git@github.com:HCA-integration/scAtlasTb.git"
  ['plots']="git@github.com:HCA-integration/scAtlasTb.git"
  ['scvi-tools']="git@github.com:HCA-integration/scAtlasTb.git"
  ['scib_accel']="git@github.com:HCA-integration/scAtlasTb.git"
  ['scib']="git@github.com:HCA-integration/scAtlasTb.git"
  ['pegasus']="git@github.com:HCA-integration/scAtlasTb.git"
  ['funkyheatmap']="git@github.com:HCA-integration/scAtlasTb.git"
  ['scgen']="git@github.com:HCA-integration/scAtlasTb.git"
)

logger_info "Working at: '$(secret_path ${PWD})'" 0
logger_info "Project: '$(secret_path ${PATH_PROJECT})'" 0

################################################################################
logger_info "Jupyter" ##########################################################
################################################################################

# Install JupyterLab and its extensions
if [[ -z "$(command -v jupyter)" ]]; then
  logger_info "Installing JupyterLab"
  ${PKG_MAN} install -y jupyterlab
else
  logger_info "JupyterLab is already installed" 0
fi

# Extensions - check if installed first
EXTENSION="nb_black"
if ! pip list 2>/dev/null | grep -q "${EXTENSION}"; then
  # ! jupyter labextension list 2>/dev/null | grep -q " ${EXTENSION} "
  logger_info "Installing JupyterLab extension: ${EXTENSION}"
  URL="git+https://github.com/leifdenby/nb_black/#egg=nb_black"
  # python -m pip install "${URL}"
fi

############################################################
logger "Downloading repositories" ##########################
############################################################

source "${PATH_BASE}/utils.sh"
setup_env_fetch_repos "${PATH_PROJECT}" "GIT_REPOS"

############################################################
logger "Creating environmets" ##############################
############################################################

setup_env_create "${PATH_PROJECT}"

############################################################
logger_info "R packages" ###################################
############################################################

source "${PATH_BASE}/setup_envs_r.sh"

############################################################
logger "Adding kernels" ####################################
############################################################

setup_env_add_kernels "${PATH_PROJECT}"

jupyter kernelspec list