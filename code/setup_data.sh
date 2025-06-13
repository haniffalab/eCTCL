#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Data copy.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-05-29 Thu 10:40:25 BST
# updated: 2025-05-29
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

################################################################################
## Environment setup ###########################################################
################################################################################

set -e

SOURCE_FILES=(
  "$(dirname $0)/logger.sh" # logger
  "$(dirname $0)/utils.sh"  # path_project, hidden_vars
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    TEMP="Sourcing '${SOURCE_FILE}'"
    [ -f "$(which logger)" ] && logger -s ${TEMP} || logger ${TEMP}
    source ${SOURCE_FILE}
  fi
done

################################################################################
logger "Global configuration" ##################################################
################################################################################

SCRIPT_DIR="$(path_project)"
echo "Working at: '${SCRIPT_DIR}'"

mkdir -p data/raw
mkdir -p data/processed

################################################################################
logger "Main" ##################################################################
################################################################################


############################################################
logger Xenium data 60 ######################################
############################################################

PATH_IMAGING="$(hidden_vars "PATH_IMAGING" "${SCRIPT_DIR}/data/variables.txt")"
DATA_PATHS=(
  "${PATH_IMAGING}/20240815_SGP177_hSkin_CTCL"
  "${PATH_IMAGING}/20241115_SGP206_hImmunoOnc_CTCL_WARTS"
)
DTYPE=xenium
SFILTER="AX.*SKI|P677|p677"

for DATA_PATH in "${DATA_PATHS[@]}"; do
  SPATHS=($(ls -d ${DATA_PATH}/*output* --color=never | grep -E "${SFILTER}"))
  LPATH=${SCRIPT_DIR}/data/raw/${DTYPE}_CTCL
  mkdir -p ${LPATH}
  for SPATH in ${SPATHS[@]}; do
    SPATH1=${LPATH}/$(basename ${SPATH})
    if [[ -L ${SPATH1} ]]; then
      unlink ${SPATH1}
    fi
    ln -s ${SPATH/%\//} ${SPATH1}
  done
done

############################################################
logger Copying data to local machine 60 ####################
############################################################

# We are sending the data to a local machine using rsync.
# This is useful for large datasets that need to be processed locally.
# We will copy the data from the remote machine to the local machine.

PATH_DATA=($(ls -d ${SCRIPT_DIR}/data/raw/${DTYPE}_CTCL/*))
# iterate the first three elements of PATH_DATA
for PATH_I in "${PATH_DATA[@]}"; do
  echo PATH_I="${PATH_I}"
  echo rsync -auvh --progress \
    --exclude-from='"config/cellranger_exclude.txt"' \
    "${USER}@${HOSTNAME}:\${PATH_I}/" \
    "\${PATH_I/#\${SCRIPT_DIR}\//}/"
done

############################################################
logger "Fetch suspension data" 60 ##########################
############################################################

URL="https://storage.googleapis.com/haniffalab/ctcl/CTCL_all_final_portal_tags.h5ad"
PATH_DATA="${SCRIPT_DIR}/data/processed/Ruoyan_2024_suspension.h5ad"

if [[ -z "$(command -v wget)" ]]; then
  curl "${URL}" --output "${PATH_DATA}"
else
  wget "${URL}" --output-file "${PATH_DATA}"
fi