#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Analysis of Xenium data.
# purpose: This script is designed to perform a comprehensive analysis of the 
#          Xenium data from CTCL samples.
#
# created: 2025-05-29 Thu 10:26:31 BST
# updated: 2025-12-09
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
# export P1="SGP273_RUN1"; export PDEBUG="debug"; source code/xenium_workflow.sh
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
#region ########################################################################

## run-time parameters -------------------------------------
# -e error, -u unset variables as error, -o pipefail error
#if any command fails
# set -euo pipefail
set -o ignoreeof

## Logger --------------------------------------------------
unset logger; unset logger_info
logger_info () { logger -t "INFO [$(basename "$0"):$LINENO]" -s "$@"; }

## Source files --------------------------------------------
[ -z "${PS1:-}" ] && export PATH_BASE="$(dirname "$0")" || export PATH_BASE=codes/${USER}
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
  file_sync "original" "${SOURCE_FILE}" # update original
done

################################################################################
## Global configuration ########################################################
#region ########################################################################

PATH_PROJECT="$(path_project)"

# Selecting subset of the dataset
case "${P1}" in
  # exclude skin and 5K panel -> take immuno-oncology samples - EXCLUDE="20240815|20250227";
  "SGP206_RUN1") DATASET_SUB="SGP206_RUN1"; RMEM=(5000 6000);;
  # exclude immuno-oncology, 5K panel -> take skin samples - EXCLUDE="20241115|20250227";
  "SGP177_RUN1") DATASET_SUB="SGP177_RUN1"; RMEM=(5000 15000);;
  # exclude skin and immuno-oncology -> take 5K samples - EXCLUDE="20240815|20241115";
  "SGP218_RUN1") DATASET_SUB="SGP218_RUN1"; RMEM=(25000 40000);;
  "SGP273_RUN1") DATASET_SUB="SGP273_RUN1"; RMEM=(25000 40000);;
esac

PATH_RAW="${PATH_PROJECT}/data/raw"
PATH_PRC="${PATH_PROJECT}/data/processed"

function setup_subset () {
  export NAME_DATASET="sp_ctcl_${DATASET_SUB}"
  export PATH_DATASET="sp_ctcl/${DATASET_SUB}"
  export PATH_RESULTS="${PATH_PROJECT}/$(
    secret_vars output_dir "${PATH_PROJECT}/config/sp_defaults.yaml"
  )"
  export ANNBENCH="$(realpath ${PATH_PROJECT}/../sc2sp_benchmark)"
  export REF_DATA="${PATH_PRC}/ruoyan_2024_suspension.h5ad"
  export REF_LABELS="cell_type"
  export INPUT_FEATURES="$(find ${PATH_RAW}/${PATH_DATASET} -name "gene_panel.json" | head -n1)"
  export PANEL_NAME=$(
    grep -m1 "design_id" ${INPUT_FEATURES} |
    awk '{gsub(/,|"/,""); print $2}' | sed 's/_/-/g'
  )
  RID="$(basename ${REF_DATA%.*})/${REF_LABELS}"
  REF_PKL="./results/${NAME_DATASET}~celltypist~${RID}/reference.pkl"
}

function job_gpu () {
  bsub -G ${LSB_DEFAULTGROUP} \
    -Is -n${1-1} -q gpu-normal `# interactive, cores, queue` \
    -gpu "num=${1-1}:gmem=${2-25G}:mode=shared" \
    -R "select[mem>${2-25G}] rusage[mem=${2-25G}]" -M${2-25G} \
    -a "memlimit=True" -W7:00 -J ${STY} \
    "$@"
}

function job_cpu () {
  bsub -G ${LSB_DEFAULTGROUP} \
    -Is -n${1-1} -q normal `# interactive, cores, queue` \
    -R "select[mem>${2}] rusage[mem=${2}]" -M${2} \
    -a "memlimit=True" -W7:30 -J ${STY} \
    "$@"
}

mkdir -p ".logs/${NAME_DATASET}"

#endregion #####################################################################
logger_info "Running workflow for '${NAME_DATASET}'" ###########################
#region ########################################################################

logger_info "Working at: '$(secret_path ${PWD})'" 0
logger_info "Project: '$(secret_path ${PATH_PROJECT})'" 0
logger_info "scAtlasTb results: '$(secret_path ${PATH_RESULTS})'" 0

shopt -s nocasematch
if [[ -n "${PDEBUG}" ]]; then
  logger_debug "Debug mode enabled, skipping workflow execution" 0
  return 0
fi
shopt -u nocasematch

#endregion #####################################################################
logger_info "Space Ranger summary" #############################################
#region ########################################################################

${PKG_MAN} activate "env_r"

NAME_SUPERSET=sp_ctcl
OUTPUTS_PATH=$(
  ls -d ${PATH_PROJECT}/results/${NAME_SUPERSET}_metrics-summary* | head -n1
) > /dev/null 2>&1 || echo ""
if [[ ! -d "${OUTPUTS_PATH}" ]]; then
  logger_info "Running Space Ranger summary: '${NAME_SUPERSET}'" 0
  Rscript ${PATH_PROJECT}/code/ranger_summary.R --name="${NAME_SUPERSET}" \
    --input="${PATH_RAW}/sp_ctcl"
else
  logger_info "Skipping Space Ranger summary, already done at:" 0
  echo -e "${OUTPUTS_PATH}"
fi

Rscript ${PATH_PROJECT}/code/ranger_summary.R --name="sp_ctcl_hAtlas" \
    --input="${PATH_RAW}/sp_ctcl" --include="SGP218|SGP273"

# This will be hardcoded for now, as we want to compare two specific datasets
TEMP="${PATH_PROJECT}/eCTCL/data/raw/xenium_CTCL_hImmune-v1,\
${PATH_PROJECT}/../PCNSL/data/raw/xenium_BRA"

OUTPUTS_PATH=$(
  ls -d ${PATH_PROJECT}/results/eCTCL-PCNSL_metrics-summary* | head -n1
) > /dev/null 2>&1 || echo ""
if [[ ! -d "${OUTPUTS_PATH}" ]]; then
  logger_info "Running Space Ranger summary: 'eCTCL-PCNSL'" 0
  Rscript ${PATH_PROJECT}/code/ranger_summary.R --name="eCTCL-PCNSL" \
    --input="${TEMP}"
else
  logger_info "Skipping Space Ranger summary, already done at:" 0
  echo -e "${OUTPUTS_PATH}"
fi

${PKG_MAN} deactivate

#endregion #####################################################################
logger_info "Quality control" ##################################################
#region ########################################################################

${PKG_MAN} activate "scqooc"

SCQOOC="$(realpath ${PATH_PROJECT}/../scqooc)"
FNAME="${SCQOOC}/code/bsub.sh"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

bash ${FNAME} --template "${SCQOOC}/analysis/quality_control.ipynb" \
  --run_path "${PATH_RAW}/${PATH_DATASET}" \
  --output "${PATH_PROJECT}/analysis/${NAME_DATASET}_quality_control" \
  --env "scqooc" --mem "${RMEM[0]}" \
  2>&1 | tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

#endregion #####################################################################
logger_info "Annotation with CellTypist" #######################################
#region ########################################################################

${PKG_MAN} activate "celltypist"

############################################################
logger_info "Training model for '${PANEL_NAME}'" 60 "-" ####
############################################################

setup_subset

FNAME="${ANNBENCH}/code/celltypist_training.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

if [[ ! -f ${REF_PKL} ]]; then
  logger_info "Training CellTypist reference" 0
  LNAME=".logs/${NAME_DATASET}/${LNAME0}_${RID//\//.}"
  bsub -G ${LSB_DEFAULTGROUP} \
    -o ${LNAME}_$(date '+%Y%m%d').out \
    -e ${LNAME}_$(date '+%Y%m%d').err \
    -n1 -q basement \
    -R "select[mem>${RMEM[1]}] rusage[mem=${RMEM[1]}]" -M "${RMEM[1]}" \
    -W30:30 -J "$(basename ${LNAME})" \
    python ${FNAME} --input="${REF_DATA}" \
      --output="results/${NAME_DATASET}" \
      --labels="${REF_LABELS}" \
      --features=${INPUT_FEATURES}
else
  logger_info "CellTypist reference already exists, skipping" 0
  echo "${REF_PKL}"
fi

############################################################
logger_info "Mapping data to celltypist reference" 60 "-" ##
############################################################

setup_subset

FNAME="${ANNBENCH}/code/celltypist_transfer.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

QDATAS=($(ls -d ${PATH_PRC}/${NAME_DATASET}_qc/*))
for QDATA in ${QDATAS[@]}; do
  QDATA_NAME="$(basename ${QDATA%.*})"
  OUT_FNAME="$(dirname ${REF_PKL})/${QDATA_NAME}.csv"
  LNAME=".logs/${NAME_DATASET}/${LNAME0}_${RID//\//.}_${QDATA_NAME}"
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

setup_subset

FNAME="${ANNBENCH}/code/merge.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

python ${FNAME} --input="$(dirname ${REF_PKL/suspension.*/})" \
  2>&1 | tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)

#endregion #####################################################################
logger_info "Annotation with NEMO" #############################################
#region ########################################################################

${PKG_MAN} activate "nemo"

FNAME="${PATH_PROJECT}/../sc2sp_benchmark/code/nemo_embed.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

QDATAS=($(ls -d ${PATH_PRC}/${NAME_DATASET}/*))
for QDATA in ${QDATAS[@]}; do
  OUT_FNAME="./results/${NAME_DATASET}~nemo/$(basename ${QDATA%.*})/adata.zarr"
  if [[ -d ${OUT_FNAME} ]]; then
    logger_info "Skipping, already processed: ${OUT_FNAME}" 0
    continue
  fi
  logger_info "Processing $(basename ${QDATA%.*})...!" 40 "@"
  LNAME=".logs/${NAME_DATASET}/${LNAME0}_$(basename ${QDATA%.*})"
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

#endregion #####################################################################
logger_info "scAtlasTb: merge" #################################################
#region ########################################################################

bash ${PATH_PROJECT}/code/scatlastb.sh merge_all \
    "${PATH_PROJECT}/config/sp_defaults.yaml" \
    "${PATH_PROJECT}/config/${NAME_DATASET}.yaml" \
    --cores 1

############################################################
logger_info "Pre-processing data" 60 "-" ###################
############################################################

bash ${PATH_PROJECT}/code/scatlastb.sh preprocessing_all \
  "${PATH_PROJECT}/config/sp_defaults.yaml" \
  "${PATH_PROJECT}/config/${NAME_DATASET}.yaml" \
  --cores 2

############################################################
logger_info "Integration" 60 "-" ###########################
############################################################

TEMP="${PATH_RESULTS}/preprocessing/\
dataset~${DATASET_SUB/-v*/}/file_id~merge:${DATASET_SUB/-v*/}"
if [[ ! -L "${TEMP}.zarr" ]]; then
  ln -s "${TEMP}/preprocessed.zarr" "${TEMP}.zarr"
fi

bash ${PATH_PROJECT}/code/scatlastb.sh integration_all \
  "${PATH_PROJECT}/config/sp_defaults.yaml" \
  "${PATH_PROJECT}/config/${NAME_DATASET}.yaml" -c2

############################################################
logger_info "Evaluation" 60 "-" ############################
############################################################

# bash ${PATH_PROJECT}/code/scatlastb.sh metrics_all \
#   ${PATH_PROJECT}/config/${NAME_DATASET}.yaml -c4

############################################################
logger_info "Merging by linking"  60 "-" ###################
############################################################

FNAME="$(realpath ${PATH_PROJECT}/src/scAtlasTb/workflow/utils/modules_merge.py)"
chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

python ${FNAME} -p "${PATH_RESULTS}" -d "${NAME_DATASET}" |
  tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)

#endregion #####################################################################
logger_info "Annotation report" ################################################
#region ########################################################################

############################################################
logger_info "Creating colour files" 60 "-" #################
############################################################

${PKG_MAN} activate "scanpy"

FNAME="${PATH_PROJECT}/code/colours_from-adata.py"; chmod +x ${FNAME}
LNAME0="$(file_log ${FNAME} ${PATH_PROJECT})"

python ${FNAME} --input="${REF_DATA}" --labels="cell_type" |
  tee -a .logs/${NAME_DATASET}/${LNAME0}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

############################################################
logger_info "Merge CellTypist results with object" 60 "-" ##
############################################################

${PKG_MAN} activate "scqooc"

setup_subset

FNAME="${ANNBENCH}/code/add2adata.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

ADATA="${PATH_RESULTS}/${DATASET_SUB/-v*/}_merged.zarr"
python ${FNAME} -a "${ADATA}" \
  -l "${PATH_PROJECT}/results/${NAME_DATASET}~celltypist"*/*.csv \
  --colours="data/metadata/ruoyan_2024_suspension_cell_type_colour.csv" \
  --metadata="data/metadata/sample.csv" |
  tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

#endregion #####################################################################
logger_info "Panel comparisons" ################################################
#region ########################################################################

############################################################
logger_info "Fetching overlaps" 60 "-" #####################
############################################################

${PKG_MAN} activate "env_r"

FNAME="${PATH_PROJECT}/code/panel_overlaps.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} | tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

############################################################
logger_info "Gathering expression data" 60 "-" #############
############################################################

${PKG_MAN} activate "scqooc"

setup_subset

FNAME="${PATH_PROJECT}/code/panel_expression-extract.py"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

PATH_PO="results/panels-10x_overlaps/overlaps_table.csv"
python ${FNAME} --input="${PATH_PO}" \
  --adata="${PATH_RESULTS}/${DATASET_SUB/-v*/}_merged_annotated.zarr" \
  --exclude="probability" \
  --output="$(dirname "${PATH_PO}")" |
  tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)


PATH_PO="results/panels-10x_overlaps/overlaps_table.csv"
python ${FNAME} --input="${PATH_PO}" \
  --adata="data/processed/suspension_ruoyan_2024_ctcl.h5ad" \
  --exclude="probability" \
  --output="$(dirname "${PATH_PO}")" |
  tee -a .logs/${NAME_DATASET}/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

############################################################
logger_info "Comparing panel expression" 60 "-" ############
############################################################

${PKG_MAN} activate "env_r"

FNAME="${PATH_PROJECT}/code/panel_expression-compare.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} --input="results/panels-10x_overlaps" \
  --table="results/panels-10x_overlaps/overlaps_table.csv" \
  --group="panel_type,sample_id,donor_id" \
  --colors="data/metadata/ruoyan_2024_suspension_cell_type_colour.csv" |
  tee -a .logs/${LNAME}_file_id_$(date +%Y%m%d%H%M%S)

Rscript ${FNAME} --input="results/panels-10x_overlaps" \
  --table="results/panels-10x_overlaps/overlaps_table.csv" \
  --group="celltypist_cell_type_majority_voting" \
  --colors="data/metadata/ruoyan_2024_suspension_cell_type_colour.csv" |
  tee -a .logs/${LNAME}_celltypist_cell_type_majority_voting_$(date +%Y%m%d%H%M%S)

############################################################
logger_info "Comparing cell type annotations" 60 "-" #######
############################################################

FNAME="${PATH_PROJECT}/code/ann_barplot.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} --input="data/processed/suspension_ruoyan_2024_ctcl_ann.csv" \
  --output="results/composition" \
  --group="study_id,donor_id,donor_id" \
  --colors="data/metadata/ruoyan_2024_suspension_cell_type_colour.csv" |
  tee -a .logs/${LNAME}_file_id_$(date +%Y%m%d%H%M%S)

Rscript ${FNAME} --input="results/panels-10x_overlaps" \
  --output="results/composition/spatial" \
  --group="panel_type,sample_short,donor_id" \
  --colors="data/metadata/ruoyan_2024_suspension_cell_type_colour.csv" |
  tee -a .logs/${LNAME}_file_id_$(date +%Y%m%d%H%M%S)

############################################################
logger_info "Comparing panel annotations" 60 "-" ###########
############################################################

FNAME="${PATH_PROJECT}/code/panel_annotations.R"; chmod +x ${FNAME}
LNAME="$(file_log ${FNAME} ${PATH_PROJECT})"

Rscript ${FNAME} --input="data/xenium-panels" \
  --output="results/panels-10x_overlaps" |
  tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

Rscript ${FNAME} --input="data/xenium-panels" \
  --subset="results/panels-10x_overlaps/overlaps_table.csv" \
  --output="results/panels-10x_overlaps" |
  tee -a .logs/${LNAME}_$(date +%Y%m%d%H%M%S)

${PKG_MAN} deactivate

#endregion #####################################################################

# Conclusions or post-processing steps

# tumor cells in the UMAP and in the spatial plot
# cancerous cells vs response T cells
# - pay attention to the healthy control
