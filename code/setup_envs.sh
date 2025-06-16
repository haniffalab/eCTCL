#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Setting up project environments.
# created: 2025-06-04 Wed 09:20:29 BST
# updated: 2025-06-04
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

################################################################################
## Environment setup ###########################################################
################################################################################

set -e

PATH_BASE=$([ -z "${PS1}" ] && echo $(dirname $0) || echo code)
SOURCE_FILES=(
  "${PATH_BASE}/logger.sh"
  "${HOME}/.conda/init.sh"
  "${PATH_BASE}/utils.sh" # PKG_MAN, path_project
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    TEMP="Sourcing '${SOURCE_FILE}'"
    [ $(type -t logger) == function ] && logger "${TEMP}" 60 || logger -s "${TEMP}"
    source ${SOURCE_FILE}
  fi
done

# Global configuration

SCRIPT_DIR="$(path_project)"
declare -A  GIT_REPOS=(
  ['scqooc']="git@github.com:cramsuig/scqooc.git"
  ['celltypist']="git@github.com:cramsuig/sc2sp_benchmark.git"
)

logger "Working at: '$(echo ${PWD} | sed 's|'"${HOME}"'|~|')'"
logger "Project: '$(echo ${SCRIPT_DIR} | sed 's|'"${HOME}"'|~|')'"
mkdir -p "${SCRIPT_DIR}/envs"

################################################################################
## Main ########################################################################
################################################################################

# Install JupyterLab and its extensions
if [[ -z "$(command -v jupyter)" ]]; then
  logger "Installing JupyterLab"
  ${PKG_MAN} install -y jupyterlab
else
  logger "JupyterLab is already installed"
fi

############################################################
logger "Downloading repositories" ##########################
############################################################

for ENV_NAME in ${!GIT_REPOS[@]}; do
  REPO_NAME=$(basename "${GIT_REPOS[${ENV_NAME}]}" .git)
  if [[ ! -d "${SCRIPT_DIR}/../${REPO_NAME}" ]]; then
    logger "Cloning repository '${REPO_NAME}'" 60
    git clone "${REPO}" "${SCRIPT_DIR}/../${REPO_NAME}"
  fi
  # Linking environment files to the envs directory
  ENV_FILE="${SCRIPT_DIR}/../${REPO_NAME}/envs/${ENV_NAME}.yaml"
  ln -s "${ENV_FILE}" "${SCRIPT_DIR}/envs/${ENV_NAME}.yaml"
done

############################################################
logger "Creating environmets" ##############################
############################################################

find ${SCRIPT_DIR}/envs/ -name "*.yaml" | while read -r ENV_FILE; do
  ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
  if ${PKG_MAN} env list | grep -q "^${ENV_NAME} "; then
    echo "Environment '${ENV_NAME}' already exists, skipping."
    continue
  fi
  logger "Creating environment '${ENV_NAME}' from '${ENV_FILE}'"
  ${PKG_MAN} env create -f "${ENV_FILE}" --name "${ENV_NAME}"
done

############################################################
logger "Adding kernels" ####################################
############################################################

find ${SCRIPT_DIR}/envs/ -name "*.yaml" | while read -r ENV_FILE; do
  ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
  if jupyter kernelspec list | grep -q " ${ENV_NAME} "; then
    ${PKG_MAN} activate ${ENV_NAME}
    if [[ $(${PKG_MAN} list | grep "^ipykernel" | wc -l) -eq 0 ]]; then
      ${PKG_MAN} install -y ipykernel
    fi
    python -m ipykernel install --user --name ${ENV_NAME} \
      --display-name "${ENV_NAME}" --user
  else
    echo "Kernel '${ENV_NAME}' already exists, skipping."
  fi
done

jupyter kernelspec list