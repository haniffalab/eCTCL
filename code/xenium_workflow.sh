#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Analysis of Xenium data.
# purpose: This script is designed to perform a comprehensive analysis of the 
#          Xenium data from CTCL samples.
#
# created: 2025-05-29 Thu 10:26:31 BST
# updated: 2025-07-24
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# Execute:
# FNAME=code/xenium_workflow.sh; chmod +x ${FNAME}; mkdir -p .logs;
# LNAME=$(echo "${FNAME/%.*/}" | sed 's|'"$(dirname ${PWD})/"'||' | tr '/' '.')
# bash ${FNAME} 2>&1 | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)
# Interactively:
# export P1="hAtlas"; export PDEBUG="debug"; source code/xenium_workflow.sh
# eval "$(sed -n '/PATTERN_BEGIN/,/PATTERN_END/p' code/xenium_workflow.sh)"

printf '\n%s\n' '
1. Environment setup        : sourcing files, logging, and package manager
2. Global configuration     : variables, paths, and directories
3. Pre-processing data.     : environments, data download, pre-processing
4. Running workflow
- 4.1 Space Ranger summary  : plotting metrics
- 4.2 Quality control       : using scqooc, reports and creating h5ad files
- 4.3 CellTypist Annotation : training models, and annotating cells
- 4.4 Normalising data      : data normalisation and log-transformation
- 4.5 Apply PCA on data     : scale and reduce dimensionality of the data
- 4.6 Merging data          : merge data for integration and locking/freeze
- 4.7 Integrating data
5. Conclusions              : post-processing, next steps, any notes
'

################################################################################
## Environment setup ###########################################################
################################################################################

## run-time parameters -------------------------------------
# -e error, -u unset variables as error, -o pipefail error
#if any command fails
# set -euo pipefail
set -o ignoreeof

## Logger --------------------------------------------------
unset logger; unset logger_info
logger_info () { logger -t "INFO [$(basename "$0"):$LINENO]" -s "$@"; }

## Source files --------------------------------------------
[ -z "${PS1:-}" ] && export PATH_BASE="$(dirname "$0")" || export PATH_BASE=code
logger_info "Using base path: ${PATH_BASE}"

SOURCE_FILES=(
  "${PATH_BASE}/utils.sh" # PKG_MAN, file_*, path_project, secret_*
  "${PATH_BASE}/logger.sh" # logger_*
  "${HOME}/.conda/init.sh"
)

for SOURCE_FILE in "${SOURCE_FILES[@]}"; do
  logger_info "Sourcing '${SOURCE_FILE}'"
  source "${SOURCE_FILE}"
  if [[ -z "$(command -v file_sync)" ]] &&
     [[ -f "${HOME}/${SOURCE_FILE}" ]]; then
    source "${HOME}/${SOURCE_FILE}"
  fi
  file_sync "${SOURCE_FILE}" # update project's
  file_sync "${HOME}/${SOURCE_FILE}" "${SOURCE_FILE}" # update original
done

################################################################################
## Global configuration ########################################################
################################################################################

PATH_PROJECT="$(path_project)"

# Selecting subset of the dataset
case "${P1}" in
  # exclude skin and 5K panel -> take immuno-oncology samples
  "hImmune") DATASET_SUB="hImmune-v1"; EXCLUDE="20240815|20250227"; RMEM=(5000 6000);;
  # exclude immuno-oncology, 5K panel -> take skin samples
  "hSkin") DATASET_SUB="hSkin-v1"; EXCLUDE="20241115|20250227"; RMEM=(5000 15000);;
  # exclude skin and immuno-oncology -> take 5K samples
  "hAtlas") DATASET_SUB="hAtlas-v1.1"; EXCLUDE="20240815|20241115"; RMEM=(25000 40000);;
esac

PATH_RAW="${PATH_PROJECT}/data/raw"
PATH_PRC="${PATH_PROJECT}/data/processed"

function setup_subset () {
  export DATASET_NAME="xenium_CTCL_${DATASET_SUB}"
  export PATH_RESULTS="${PATH_PROJECT}/$(
    secret_vars output_dir "${PATH_PROJECT}/config/${DATASET_NAME}.yaml"
  )"
  export ANNBENCH="$(realpath ${PATH_PROJECT}/../sc2sp_benchmark)"
  export REF_DATA="${PATH_PRC}/ruoyan_2024_suspension.h5ad"
  export REF_LABELS="cell_type"
  export INPUT_FEATURES="$(ls ${PATH_RAW}/${DATASET_NAME}/*/gene_panel.json | head -n1)"
  export PANEL_NAME=$(
    grep -m1 "design_id" ${INPUT_FEATURES} |
    awk '{gsub(/,|"/,""); print $2}' | sed 's/_/-/g'
  )
  export QDATAS=($(ls -d ${PATH_PRC}/${DATASET_NAME}/*))
  RID="$(basename ${REF_DATA%.*})/${REF_LABELS}"
  REF_PKL="./results/${DATASET_NAME}~celltypist~${RID}/reference.pkl"
}

mkdir -p ".logs/${DATASET_NAME}"

################################################################################
logger_info "Running workflow for '${DATASET_NAME}'" ###########################
################################################################################

logger_info "Working at: '$(secret_path ${PWD})'" 0
logger_info "Project: '$(secret_path ${PATH_PROJECT})'" 0
logger_info "scAtlasTb results: '$(secret_path ${PATH_RESULTS})'" 0

shopt -s nocasematch
if [[ -n "${PDEBUG}" ]]; then
  logger_debug "Debug mode enabled, skipping workflow execution" 0
  return 0
fi
shopt -u nocasematch

################################################################################
logger_info "Space Ranger summary" #############################################
################################################################################

${PKG_MAN} activate "env_r"

OUTPUTS_PATH=$(
  ls -d ${PATH_PROJECT}/results/${DATASET_NAME/_h*/}_metrics-summary* | head -n1
) > /dev/null 2>&1 || echo ""
if [[ ! -d "${OUTPUTS_PATH}" ]]; then
  logger_info "Running Space Ranger summary: '${DATASET_NAME}'" 0
  Rscript ${PATH_PROJECT}/code/spaceranger_summary.R --name="${DATASET_NAME}" \
    --input="${PATH_RAW}/${DATASET_NAME}"
else
  logger_info "Skipping Space Ranger summary, already done at:" 0
  echo -e "${OUTPUTS_PATH}"
fi

# This will be hardcoded for now, as we want to compare two specific datasets
TEMP="${PATH_PROJECT}/eCTCL/data/raw/xenium_CTCL_hImmune-v1,\
${PATH_PROJECT}/../PCNSL/data/raw/xenium_BRA"

OUTPUTS_PATH=$(
  ls -d ${PATH_PROJECT}/results/eCTCL-PCNSL_metrics-summary* | head -n1
) > /dev/null 2>&1 || echo ""
if [[ ! -d "${OUTPUTS_PATH}" ]]; then
  logger_info "Running Space Ranger summary: 'eCTCL-PCNSL'" 0
  Rscript ${PATH_PROJECT}/code/spaceranger_summary.R --name="eCTCL-PCNSL" \
    --input="${TEMP}"
else
  logger_info "Skipping Space Ranger summary, already done at:" 0
  echo -e "${OUTPUTS_PATH}"
fi

${PKG_MAN} deactivate

################################################################################
logger_info "Quality control" ##################################################
################################################################################

SCQOOC="$(realpath ${PATH_PROJECT}/../scqooc)"
FNAME="${SCQOOC}/code/bsub.sh"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

bash ${FNAME} --template "${SCQOOC}/analysis/quality_control.ipynb" \
  --run_path "${PATH_RAW}/${DATASET_NAME}" \
  --output "${PATH_PROJECT}/analysis/${DATASET_NAME}_quality_control" \
  --env "scqooc" --mem "${RMEM[0]}" \
  2>&1 | tee -a .logs/${DATASET_NAME}/${LNAME}_$(date +%Y%m%d%H%M%S)

################################################################################
logger_info "Annotation with CellTypist" #######################################
################################################################################

${PKG_MAN} activate "celltypist"

############################################################
logger_info "Training model for '${PANEL_NAME}'" 60 "-" ####
############################################################

setup_subset

FNAME="${ANNBENCH}/code/celltypist_training.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

if [[ ! -f ${REF_PKL} ]]; then
  logger_info "Training CellTypist reference" 0
  LNAME=".logs/${DATASET_NAME}/${LNAME0}_${RID//\//.}"
  bsub -G ${LSB_DEFAULTGROUP} \
    -o ${LNAME}_$(date '+%Y%m%d').out \
    -e ${LNAME}_$(date '+%Y%m%d').err \
    -n1 -q basement \
    -R "select[mem>${RMEM[1]}] rusage[mem=${RMEM[1]}]" -M "${RMEM[1]}" \
    -W30:30 -J "$(basename ${LNAME})" \
    python ${FNAME} --input="${REF_DATA}" \
      --output="results/${DATASET_NAME}" \
      --labels="${REF_LABELS}" \
      --features=${INPUT_FEATURES}
else
  logger_info "CellTypist reference already exists, skipping" 0
  echo "${REF_PKL}"
fi

############################################################
logger_info "Mapping data to celltypist reference" 60 "-" ##
############################################################

FNAME="${ANNBENCH}/code/celltypist_transfer.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

for QDATA in ${QDATAS[@]}; do
  QDATA_NAME="$(basename ${QDATA%.*})"
  OUT_FNAME="$(dirname ${REF_PKL})/${QDATA_NAME}_ann.csv"
  LNAME=".logs/${DATASET_NAME}/${LNAME0}_${RID//\//.}_${QDATA_NAME}"
  # check if job is runing (hide error or other messages by bjob)
  TEMP="$(bjobs -l | grep $(basename ${LNAME}) | wc -l)"
  if [[ ! -f ${OUT_FNAME} ]] && [[ "${TEMP}" -lt 1 ]]; then
    logger_info "Processing '${QDATA_NAME}'..." 40 "@"
    TEMP="$(du -hs ${QDATA} | awk '{print $1}' | sed 's/[^0-9]*//g')"
    JMEM=10000
    if [[ "${TEMP}" -gt 100 ]]; then
      logger_warn "Large dataset, increasing memory" 0
      JMEM=25000
    fi
    bsub -G ${LSB_DEFAULTGROUP} \
        -o ${LNAME}_$(date '+%Y%m%d').out \
        -e ${LNAME}_$(date '+%Y%m%d').err \
        -n1 -q normal \
        -R "select[mem>${JMEM}] rusage[mem=${JMEM}]" \
        -M ${JMEM} \
        -W2:30 -J "$(basename ${LNAME})" \
        python ${FNAME} --reference="${REF_PKL}" --query="${QDATA}"
  fi
done

############################################################
logger_info "Merge CellTypist results" 60 "-" ##############
############################################################

FNAME="${ANNBENCH}/code/merge.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

python ${FNAME} --input="$(dirname ${REF_PKL/suspension.*/})" \
  2>&1 | tee -a .logs/${DATASET_NAME}/${LNAME}_$(date +%Y%m%d%H%M%S)

################################################################################
logger_info "Annotation with NEMO" #############################################
################################################################################

${PKG_MAN} activate "nemo"

FNAME="${PATH_PROJECT}/../sc2sp_benchmark/code/nemo_embed.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

QDATAS=($(ls -d ${PATH_PRC}/${DATASET_NAME}/*))
for QDATA in ${QDATAS[@]}; do
  OUT_FNAME="./results/${DATASET_NAME}~nemo/$(basename ${QDATA%.*})/adata.zarr"
  if [[ -d ${OUT_FNAME} ]]; then
    logger_info "Skipping, already processed: ${OUT_FNAME}" 0
    continue
  fi
  logger_info "Processing $(basename ${QDATA%.*})...!" 40 "@"
  LNAME=".logs/${DATASET_NAME}/${LNAME0}_$(basename ${QDATA%.*})"
  bsub -G ${LSB_DEFAULTGROUP} \
        -o ${LNAME}_$(date '+%Y%m%d').out \
        -e ${LNAME}_$(date '+%Y%m%d').err \
        -n1 -q normal \
        -R "select[mem>70] rusage[mem=70]" \
        -M 70 \
        -W2:30 -J "$(basename ${LNAME})" \
        python ${FNAME} --input="${QDATA}"
done

${PKG_MAN} deactivate

################################################################################
logger_info "scAtlasTb: merge" #################################################
################################################################################

bash ${PATH_PROJECT}/code/scatlastb.sh merge_all \
  "${PATH_PROJECT}/config/${DATASET_NAME}.yaml" -c1

############################################################
logger_info "Pre-processing data" 60 "-" ###################
############################################################

bash ${PATH_PROJECT}/code/scatlastb.sh preprocessing_all \
  "${PATH_PROJECT}/config/${DATASET_NAME}.yaml" -c2

############################################################
logger_info "Integration" 60 "-" ###########################
############################################################

TEMP="${PATH_RESULTS}/preprocessing/\
dataset~${DATASET_SUB/-v*/}/file_id~merge:${DATASET_SUB/-v*/}"
if [[ ! -L "${TEMP}.zarr" ]]; then
  ln -s "${TEMP}/preprocessed.zarr" "${TEMP}.zarr"
fi

bash ${PATH_PROJECT}/code/scatlastb.sh integration_all \
  ${PATH_PROJECT}/config/${DATASET_NAME}.yaml -c2

# ############################################################
logger_info "Evaluation" 60 "-" ##############################
# ############################################################

# bash ${PATH_PROJECT}/code/scatlastb.sh metrics_all \
#   ${PATH_PROJECT}/config/${DATASET_NAME}.yaml -c4

############################################################
logger_info "Merging by linking"  60 "-" ###################
############################################################

FNAME="$(realpath ${PATH_PROJECT}/src/scAtlasTb/workflow/utils/modules_merge.py)"
chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

python ${FNAME} -p "${PATH_RESULTS}" -d "${DATASET_NAME}" |
  tee -a .logs/${DATASET_NAME}/${LNAME}_$(date +%Y%m%d%H%M%S)

################################################################################
logger_info "Merge CellTypist results with object" #############################
################################################################################

${PKG_MAN} activate "scqooc"

setup_subset

FNAME="${ANNBENCH}/code/add2adata.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

ADATA="${PATH_RESULTS}/${DATASET_SUB/-v*/}_merged.zarr"
python ${FNAME} -a "${ADATA}" \
  -l "${PATH_PROJECT}/results/${DATASET_NAME}~celltypist"*/*.csv |
  tee -a .logs/${DATASET_NAME}/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

################################################################################
logger_info "Label transfer report" ############################################
################################################################################

${PKG_MAN} activate "scqooc"

setup_subset

FNAME="${ANNBENCH}/code/celltypist_report.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

ADATA="${PATH_RESULTS}/${DATASET_SUB/-v*/}_merged_annotated.zarr"
python ${FNAME} --input="${ADATA}" --samples="file_id" |
  tee -a .logs/${DATASET_NAME}/${LNAME0}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

################################################################################
logger_info "Panel comparisons" ################################################
################################################################################

${PKG_MAN} activate "env_r"

FNAME="${PATH_PROJECT}/code/panel_overlaps.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

${PKG_MAN} activate "scqooc"

FNAME="${PATH_PROJECT}/code/panel_expression-extract.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

PATH_PO="results/panels-10x_overlaps/overlaps_table.csv"
python ${FNAME} --input="${PATH_PO}" \
  --adata="${PATH_RESULTS}/${DATASET_SUB/-v*/}_merged_annotated.zarr" \
  --exclude="probability" \
  --output="$(dirname "${PATH_PO}")" |
  tee -a .logs/${DATASET_NAME}/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

${PKG_MAN} activate "env_r"

FNAME="${PATH_PROJECT}/code/panel_expression-compare.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} --input="results/panels-10x_overlaps/hAtlas_merged_annotated.csv" |
  tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

# Conclusions or post-processing steps

# tumor cells in the UMAP and in the spatial plot
# cancerous cells vs response T cells
# - pay attention to the healthy control
