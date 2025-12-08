#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Data copy.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-05-29 Thu 10:40:25 BST
# updated: 2025-07-24
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# eval "$(grep -B 100 "Xenium data" code/setup_data.sh)"
# export PDEBUG="debug"; source code/setup_data.sh
# eval "$(sed -n '/PATTERN_BEGIN/,/PATTERN_END/p' code/setup_data.sh)"

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
logger_info() { logger -t "INFO [$(basename "$0"):$LINENO]" -s "$@"; }

## Source files --------------------------------------------
[ -z "${PS1:-}" ] && export PATH_BASE="$(dirname "$0")" || export PATH_BASE=code
logger_info "Using base path: ${PATH_BASE}"

SOURCE_FILES=(
  "${PATH_BASE}/logger.sh" # logger_*
  "${PATH_BASE}/utils.sh"  # file_sync, path_project, secret_*
  "${PATH_BASE}/utils_setup.sh"  # download_data
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
logger_info "Global configuration" #############################################
################################################################################

PATH_PROJECT="$(path_project)"
PATH_SCRATCH="$(secret_vars "PATH_SCRATCH" "${PATH_PROJECT}/data/variables.txt")"
PATH_SCRATCH="${PATH_SCRATCH}/$(basename ${PATH_PROJECT})"

logger_info "Working at: '$(secret_path ${PWD})'" 0
logger_info "Project: '$(secret_path ${PATH_PROJECT})'" 0

bash ${HOME}/code/project_create.sh "${PATH_PROJECT}" "${PATH_SCRATCH}"

shopt -s nocasematch
if [[ -n "${PDEBUG}" ]]; then
  logger_debug "Debug mode enabled, skipping workflow execution" 0
  return 0
fi
shopt -u nocasematch

################################################################################
logger_info "Xenium data" ######################################################
################################################################################

PATH_IMG_BASE="$(secret_vars "PATH_IMAGING" "${PATH_PROJECT}/data/variables.txt")"
declare -A PATH_IMAGING=(
  ['b0_hSkin']="${PATH_IMG_BASE}/20240815_SGP177_hSkin_CTCL"
  ['b0_hImmune']="${PATH_IMG_BASE}/20241115_SGP206_hImmunoOnc_CTCL_WARTS"
  ['b0_hAtlas']="${PATH_IMG_BASE}/20250227_SGP218_5K_BCN+CTCL_FFPE/CTCL FFPE"
  ['b1_hAtlas']="${PATH_IMG_BASE}/20250724_SGP273_5K_earlyCTCL/20250724_SGP273_5K_CTCL_Run1"
  ['b2_hAtlas']="${PATH_IMG_BASE}/20250724_SGP273_5K_earlyCTCL/20251110__143927__SGP273_run2"
  ['b3_hAtlas']="${PATH_IMG_BASE}/20250724_SGP273_5K_earlyCTCL/20251110__142107__SGP273_run3"
  ['b3_hAtlas']="${PATH_IMG_BASE}/20250724_SGP273_5K_earlyCTCL/20251117__133339__SGP273_run4"
  ['b5_hAtlas']="${PATH_IMG_BASE}/20250724_SGP273_5K_earlyCTCL/20251117__140414__SGP273_run5"
)
# "SGP219|SGP238|SGP245|SGP279|SGP247"

setup_data_copy "PATH_IMAGING" \
  "${PATH_SCRATCH}/data/raw/sp_ctcl" \
  "*output-*" \
  "AX.*SKI|P677|p677|DG.*SK" # include

################################################################################
logger_info "Fetch suspension data" ############################################
################################################################################

URL="https://storage.googleapis.com/haniffalab/ctcl/CTCL_all_final_portal_tags.h5ad"
PATH_DATA="${PATH_SCRATCH}/data/processed/suspension_ruoyan_2024_ctcl.h5ad"

if [[ ! -f "${PATH_DATA}" ]]; then
  download_data "${URL}" "${PATH_DATA}"
fi

if [[ ! -L "${PATH_PROJECT}/data/processed/$(basename ${PATH_DATA})" ]]; then
  logger_info "Linking suspension data to project" 0
  ln -s "${PATH_DATA}" "${PATH_PROJECT}/data/processed/"
fi

################################################################################
logger_info "Fetch gene panel tables" ##########################################
################################################################################

DATA_PREFIX="https://cdn.10xgenomics.com/raw/upload/"
DATA_MIDFIX="software-support/Xenium-panels"
DATA_SUFFIX="_metadata.csv"

declare -A URLS
URLS['hSkin-v1']="${DATA_PREFIX}/v1699308550/${DATA_MIDFIX}/\
hSkin_panel_files/Xenium_hSkin_v1${DATA_SUFFIX}"
URLS['hImmune-v1']="${DATA_PREFIX}/v1706911412/${DATA_MIDFIX}/\
hImmuno_Oncology_panel_files/Xenium_hIO_v1${DATA_SUFFIX}"
URLS['hAtlas-v1.1']="${DATA_PREFIX}/v1715726653/${DATA_MIDFIX}/\
5K_panel_files/XeniumPrimeHuman5Kpan_tissue_pathways${DATA_SUFFIX}"

mkdir -p "${PATH_SCRATCH}/data/xenium-panels"
for PANEL in "${!URLS[@]}"; do
  logger_info "Fetching xenium panel '${PANEL}'" 0
  URL="${URLS[${PANEL}]}"
  PATH_DATA="${PATH_SCRATCH}/data/xenium-panels/${PANEL}.csv"
  download_data "${URL}" "${PATH_DATA}"
done

if [[ ! -L "${PATH_PROJECT}/data/xenium-panels" ]]; then
  logger_info "Linking xenium panels data to project" 0
  ln -s "${PATH_SCRATCH}/data/xenium-panels" "${PATH_PROJECT}/data/"
fi

logger_info "Data setup completed"