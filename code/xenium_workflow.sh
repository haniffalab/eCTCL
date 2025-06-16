#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# title: Analysis of Xenium data.
# purpose: This script is designed to perform a comprehensive analysis of the 
#          Xenium data from CTCL samples.
#
# created: 2025-05-29 Thu 10:26:31 BST
# updated: 2025-06-13
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

################################################################################
## Environment setup ###########################################################
################################################################################

# Quick installations --------------------------------------
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
set -e
# In-house/developing --------------------------------------
SOURCE_FILES=(
  "code/logger.sh" # logger
  "~/.conda/init.sh"
  "code/utils.sh" # ENV_CMD, script_loc
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    TEMP="Sourcing '${SOURCE_FILE}'"
    [ -f "$(which logger)" ] && logger -s ${TEMP} || logger ${TEMP} 60
    source ${SOURCE_FILE}
  fi
done
# Tool (packaged) modules ----------------------------------

################################################################################
logger "Global configuration" ##################################################
################################################################################

PATH_PROJECT="$(path_project)"
logger "Working at: '$(echo ${PWD} | sed 's|'"${HOME}"'|~|')'" 0
logger "Project: '$(echo ${PATH_PROJECT} | sed 's|'"${HOME}"'|~|')'" 0

################################################################################
logger "Pre-processing and setup data" #########################################
################################################################################

source code/setup_data.sh

################################################################################
logger "Running workflow" ######################################################
################################################################################

############################################################
logger "Space Ranger summary" 60 "-" #######################
############################################################

ENV_NAME=$(${ENV_CMD} env list | grep -E "env_r" | awk '{print $1}' | head -n1)
${ENV_CMD} activate ${ENV_NAME}

Rscript ${PATH_PROJECT}/code/spaceranger_summary.R --name="xenium_CTCL" \
  --input="${PATH_PROJECT}/data/raw/xenium_CTCL/warts" 

${ENV_CMD} deactivate

############################################################
logger "Quality control" 60 "-" ############################
############################################################

SCQOOC="${PATH_PROJECT}/../scqooc"
FNAME="${SCQOOC}/code/bsub.sh"; chmod +x ${FNAME}
LNAME="$(echo "${FNAME/%.*/}" | sed 's|'"$(dirname ${PWD})/"'||' | tr '/' '.')"
bash ${FNAME} --template "${SCQOOC}/analysis/quality_control.ipynb" \
  --run_path "${PATH_PROJECT}/data/raw/xenium_CTCL" \
  --output "${PATH_PROJECT}/analysis/quality_control" \
  2>&1 | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

############################################################ -------------------
logger "Annotation with celltypist" ######################## -------------------
############################################################ -------------------

ENV_NAME=$(${ENV_CMD} env list | grep -E "scanpy" | awk '{print $1}' | head -n1)
${ENV_CMD} activate ${ENV_NAME}
ANNBENCH="${PATH_PROJECT}/../sc2sp_benchmark"
FNAME="${ANNBENCH}/code/celltypist_training.py"; chmod +x ${FNAME}
LNAME="$(echo "${FNAME/%.*/}" | sed 's|'"$(dirname ${PWD})/"'||' | tr '/' '.')"

logger "Training model for 'Human Skin panel'" 60

INPUT_FEATURES="$(ls ${PATH_PROJECT}/data/raw/xenium_CTCL/*335*AX10*s5*/gene_panel.json)"
python ${FNAME} --input="${PATH_PROJECT}/data/processed/Ruoyan_2024_suspension.h5ad" \
  --labels="cell_type" \
  --features=${INPUT_FEATURES} \
  2>&1 | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S) &

logger "Training model for 'Immuno−Oncology panel'" 60

INPUT_FEATURES="$(ls ${PATH_PROJECT}/data/raw/xenium_CTCL/*055*AX10*S6*/gene_panel.json)"
python ${FNAME} --input="${PATH_PROJECT}/data/processed/Ruoyan_2024_suspension.h5ad" \
  --labels="cell_type" \
  --features=${INPUT_FEATURES} \
  2>&1 | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

${ENV_CMD} deactivate

############################################################
logger "Merging data" 60 "-" ###############################
############################################################

papermill ${SCQOOC}/analysis/quality_control_merging.ipynb \
  ${PATH_PROJECT}/analysis/quality_control_merge.ipynb \
  --parameters name="xenium_CTCL" \
  --parameters input="${PATH_PROJECT}/data/processed/xenium_CTCL"
  --kernel ${ENV_NAME}

############################################################
logger "Integrating data" 60 "-" ###########################
############################################################

ENV_NAME=$(${ENV_CMD} env list | grep -E "harmony" | awk '{print $1}' | head -n1)
${ENV_CMD} activate ${ENV_NAME}

python ${PATH_PROJECT}/code/integrate_harmony.py \
  --input "${PATH_PROJECT}/data/processed/xenium_CTCL/merged.zarr" \
  --output "${PATH_PROJECT}/data/processed/xenium_CTCL/merged.zarr"

################################################################################
## Conclusions #################################################################
################################################################################

# Conclusions or post-processing steps

################################################################################
## Save ########################################################################
################################################################################
