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

mkdir -p data/raw
SCRIPT_DIR="$([ -z "${PS1}" ] && echo $(realpath $(dirname $0)) || echo $(pwd))"
echo "Working at: '${SCRIPT_DIR}'"

############################################################
## Xenium data #############################################
############################################################

function hidden_vars() {
  # This function is used to extract hidden variables from a file.
  # It uses sed to match the pattern and extract the value.
  grep -E "^${1}:" ${SCRIPT_DIR}/data/variables.txt | \
    sed -E "s/${1}:(.*)/\1/" | tr -d '[:space:]'
}

PATH_IMAGING=$(hidden_vars PATH_IMAGING)
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
## Copying data to local machine ###########################
############################################################

# We are sending the data to a local machine using rsync.
# This is useful for large datasets that need to be processed locally.
# We will copy the data from the remote machine to the local machine.

PATH_DATA=($(ls -d ${SCRIPT_DIR}/data/raw/${DTYPE}_CTCL/*))
# iterate the first three elements of PATH_DATA
for PATH_I in "${PATH_DATA[@]}"; do
  echo PATH_I="${PATH_I}"
  #--dry-run \
  echo rsync -auvh --progress \
    --exclude-from='"config/cellranger_exclude.txt"' \
    "${USER}@${HOSTNAME}:\${PATH_I}/" \
    "\${PATH_I/#\${SCRIPT_DIR}\//}/"
done
