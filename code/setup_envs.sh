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

logger "Working at: '$(echo ${PWD} | sed 's|'"${HOME}"'|~|')'" 0
logger "Project: '$(echo ${SCRIPT_DIR} | sed 's|'"${HOME}"'|~|')'" 0
mkdir -p "${SCRIPT_DIR}/envs"
mkdir -p "${SCRIPT_DIR}/.logs"

################################################################################
## Main ########################################################################
################################################################################

# Install JupyterLab and its extensions
if [[ -z "$(command -v jupyter)" ]]; then
  logger "Installing JupyterLab"
  ${PKG_MAN} install -y jupyterlab
else
  logger "JupyterLab is already installed" 0
fi

############################################################
logger "Downloading repositories" ##########################
############################################################

# Make sure the git repositories are cloned
# then link the environment files to the envs directory in this project
for ENV_NAME in ${!GIT_REPOS[@]}; do
  REPO_PATH="${SCRIPT_DIR}/../$(basename "${GIT_REPOS[${ENV_NAME}]}" .git)"
  if [[ ! -d "${REPO_PATH}" ]]; then
    logger "Cloning repository '$(basename ${REPO_PATH})'" 60
    git clone "${GIT_REPOS[${ENV_NAME}]}" "${REPO_PATH}"
  fi
  REPO_PATH="$(realpath ${REPO_PATH})"
  # Linking environment files to the envs directory
  ENV_FILE0="${REPO_PATH}/envs/${ENV_NAME}.yaml"
  ENV_FILE1="${SCRIPT_DIR}/envs/${ENV_NAME}.yaml"
  [ -f "${ENV_FILE0}" ] || {
    logger_warn "No environment file '${ENV_FILE0}'"
    continue
  }
  [ ! -L ${ENV_FILE1} ] && ln -s "${ENV_FILE0}" "${ENV_FILE1}"
done

############################################################
logger "Creating environmets" ##############################
############################################################

find ${SCRIPT_DIR}/envs/ -name "*.yaml" | while read -r ENV_FILE; do
  ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
  ENV_LOG="$(echo "${ENV_FILE/%.*/}" | sed 's|'"${SCRIPT_DIR}/"'||' | tr '/' '.')"
  ENV_LOG=".logs/${ENV_LOG}_$(date +%Y%m%d%H%M%S)" # keep a log of creation
  logger "'${ENV_NAME}' from '${ENV_FILE}'" 0
  if ${PKG_MAN} env list | grep -q " ${ENV_NAME} "; then
    logger_warn "Environment '${ENV_NAME}' already exists, skipping."
    continue
  fi
  echo "Logging to: '${ENV_LOG}'"
  ${PKG_MAN} env create -y --file "${ENV_FILE}" \
    --name "${ENV_NAME}" 2>&1 > "${ENV_LOG}"
done

############################################################
logger "Adding kernels" ####################################
############################################################

find ${SCRIPT_DIR}/envs/ -name "*.yaml" | while read -r ENV_FILE; do
  ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
  if jupyter kernelspec list | grep -q " ${ENV_NAME} "; then
    logger_warn "Kernel '${ENV_NAME}' already exists, skipping." 0
  else
    ${PKG_MAN} activate ${ENV_NAME}
    if [[ "$(${PKG_MAN} list | grep "ipykernel " | wc -l)" -eq 0 ]]; then
      ${PKG_MAN} install -y ipykernel --quiet
    fi
    python -m ipykernel install --user --name ${ENV_NAME} \
      --display-name "${ENV_NAME}" --user
  fi
done

jupyter kernelspec list