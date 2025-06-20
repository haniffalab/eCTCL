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

PATH_BASE=$([ -z "${PS1}" ] && echo $(dirname $0) || echo code)
SOURCE_FILES=(
  "${PATH_BASE}/logger.sh" # logger
  "${PATH_BASE}/utils.sh"  # path_project, hidden_vars
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    TEMP="Sourcing '${SOURCE_FILE}'"
    [ $(type -t logger) == function ] && logger "${TEMP}" 60 || logger -s "${TEMP}"
    source ${SOURCE_FILE}
  fi
done

################################################################################
logger "Global configuration" ##################################################
################################################################################

PATH_PROJECT="$(path_project)"
PATH_SCRATCH="$(hidden_vars "PATH_SCRATCH" "${PATH_PROJECT}/data/variables.txt")"
PATH_SCRATCH="${PATH_SCRATCH}/$(basename ${PATH_PROJECT})"

logger "Working at: '${PATH_PROJECT}'"

PATH_MKDIR=("data/raw" "data/processed" "src")
for DIR in "${PATH_MKDIR[@]}"; do
  mkdir -p "${PATH_PROJECT}/${DIR}"
  mkdir -p "${PATH_SCRATCH}/${DIR}"
done

################################################################################
logger "Main" ##################################################################
################################################################################

############################################################
logger "Xenium data" 60 ####################################
############################################################

PATH_IMAGING="$(hidden_vars "PATH_IMAGING" "${PATH_PROJECT}/data/variables.txt")"
DATA_PATHS=(
  "${PATH_IMAGING}/20240815_SGP177_hSkin_CTCL"
  "${PATH_IMAGING}/20241115_SGP206_hImmunoOnc_CTCL_WARTS"
  "${PATH_IMAGING}/20250227_SGP218_5K_BCN+CTCL_FFPE/CTCL FFPE"
)
DTYPE=xenium
DNAME="CTCL"
LPATH=${PATH_SCRATCH}/data/raw/${DTYPE}_${DNAME}
SFILTER="AX.*SKI|P677|p677"

mkdir -p ${LPATH}
for DATA_PATH in "${DATA_PATHS[@]}"; do
  logger "Copying '$(basename "${DATA_PATH}")'" 60 "-"
  CCOUNT=0; DCOUNT=0
  while read -r SPATH;
  do
    DCOUNT=$(($DCOUNT + 1))
    logger " * $(basename "${SPATH}")" 0
    if [[ -d "${LPATH}/$(basename "${SPATH}")" ]]; then
      echo present
    fi
    # can't access it from a node, so we need to copy instead of link
    # ln -s "${SPATH/%\//}" "${SPATH1}"
    rsync -auvh --progress --exclude "analysis" "${SPATH/%\//}" "${LPATH}/"
    CCOUNT=$(($CCOUNT + 1))
  done <<< "$(
    find "${DATA_PATH}" -maxdepth 1 -name "*output*" -type d | grep -E "${SFILTER}"
  )"
  printf "${CCOUNT}/${DCOUNT} copied '${LPATH}'\n"
done
if [[ ! -L "${PATH_PROJECT}/data/raw/${DTYPE}_${DNAME}" ]]; then
  logger "Linking scratch data to project" 0
  ln -s "${PATH_SCRATCH}/data/raw/${DTYPE}_${DNAME}" \
    "${PATH_PROJECT}/data/raw/"
fi

############################################################
logger "Commands to copy data to local machine" 60 #########
############################################################

TEMP="${PATH_PROJECT}/src/cellranger_rsync.sh"
printf '
We are sending the data to a local machine using rsync.
Copying data to local machine commands: "'${TEMP}'".\n
'

echo "#!/usr/bin/env bash" > "${TEMP}"
PATH_DATA=($(ls -d ${PATH_PROJECT}/data/raw/${DTYPE}_${DNAME}/*))
# iterate the first three elements of PATH_DATA
for PATH_I in "${PATH_DATA[@]}"; do
  echo PATH_I="${PATH_I}" >> "${TEMP}"
  echo rsync -auvh --progress \
    --exclude-from='"config/cellranger_exclude.txt"' \
    "${USER}@${HOSTNAME}:\${PATH_I}/" \
    "\${PATH_I/#\${PATH_PROJECT}\//}/" >> "${TEMP}"
done

############################################################
logger "Fetch suspension data" 60 ##########################
############################################################

URL="https://storage.googleapis.com/haniffalab/ctcl/CTCL_all_final_portal_tags.h5ad"
PATH_DATA="${PATH_SCRATCH}/data/processed/ruoyan_2024_suspension.h5ad"

if [[ ! -f "${PATH_DATA}" ]]; then
  if [[ -z "$(command -v wget)" ]]; then
    logger "Downloading data using curl" 0
    curl "${URL}" --output "${PATH_DATA}"
  else
    logger "Downloading data using wget" 0
    wget "${URL}" --output-document "${PATH_DATA}"
  fi
fi
if [[ ! -L "${PATH_PROJECT}/data/processed/$(basename ${PATH_DATA})" ]]; then
  logger "Linking suspension data to project" 0
  ln -s "${PATH_DATA}" "${PATH_PROJECT}/data/processed/"
fi

logger "Data setup completed"