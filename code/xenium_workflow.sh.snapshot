#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# title: Analysis of Xenium data.
# purpose: This script is designed to perform a comprehensive analysis of the 
#          Xenium data from CTCL samples.
#
# created: 2025-05-29 Thu 10:26:31 BST
# updated: 2025-05-29
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# Execute:
# FNAME=code/xenium_workflow.sh; chmod +x ${FNAME}
# bash ${FNAME} 2>&1 | tee -a .logs/${FNAME/\//.}_$(date +%Y%m%d%H%M%S)

## Environment setup ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Quick installations --------------------------------------
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
set -e
# In-house/developing --------------------------------------
SOURCE_FILES=(
  "code/logger.sh"
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    echo "Sourcing ${SOURCE_FILE}"
    source ${SOURCE_FILE}
  fi
done
# Tool (packaged) modules ----------------------------------

## Global configuration ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
SCRIPT_DIR="$([ -z "${PS1}" ] && echo $(realpath $(dirname $0)) || echo $(pwd))"
logger "Working at: '${SCRIPT_DIR}'"

################################################################################
logger "Pre-processing and setup data" #########################################
################################################################################

source code/setup_data.sh

################################################################################
logger "Running workflow" ######################################################
################################################################################

############################################################
## Quality control #########################################
############################################################

logger "Quality control checks on the Xenium data" 60
SCQOOC=${HOME}/group-haniffa/scqooc
FNAME=${SCQOOC}/code/bsub.sh; chmod +x ${FNAME}
bash ${FNAME} --template "${SCQOOC}/analysis/quality_control.ipynb" \
  --run_path "data/raw/CTCL_xenium" \
  --output "analysis/quality_control" \
  --dry \
  2>&1 | tee -a .logs/${FNAME/\//.}_$(date +%Y%m%d%H%M%S)

################################################################################
## Conclusions #################################################################
################################################################################

# Conclusions or post-processing steps

################################################################################
## Save ########################################################################
################################################################################
