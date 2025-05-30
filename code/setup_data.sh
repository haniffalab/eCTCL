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

############################################################
## Xenium data #############################################
############################################################


DATA_PATHS=(
  /nfs/t298_imaging/0XeniumExports/20240815_SGP177_hSkin_CTCL
  /nfs/t298_imaging/0XeniumExports/20241115_SGP206_hImmunoOnc_CTCL_WARTS
)
DTYPE=xenium

for DATA_PATH in "${DATA_PATHS[@]}"; do
  LPATH=${WORKDIR}/data/raw/CTCL_${DTYPE}
  mkdir -p ${LPATH}
  for SPATH in `ls -d ${DATA_PATH}/*/output* --color=never`; do
    SPATH1=${LPATH}/${SPATH##*/}
    if [[ -f ${SPATH1} ]]; then
      unlink ${SPATH1}
    fi
    ln -s ${SPATH} ${SPATH1}
  done
done