#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Script cook.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-07-01 Tue 11:03:47 BST
# updated: 2025-08-26
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

PATH_BASE=$([ -z "${PS1}" ] && echo $(dirname $0) || echo code)
SOURCE_FILES=(
  "${PATH_BASE}/utils.sh" # PKG_MAN, path_project
  "${PATH_BASE}/logger.sh" # logger_info
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

${PKG_MAN} activate snakemake

PATH_PROJECT="$(path_project)"
PIPELINE=$(realpath ${PATH_PROJECT}/../scAtlasTb)

# Iterate over the arguments until a YAML file is found
echo "Original args: $@"
export CONFIG_FILE=""
# Remove all occurrences of --debug
filtered_args=()
for arg in "$@"; do
  if [[ "$arg" == *.yaml ]]; then
    CONFIG_FILE+="$(realpath "$arg") "
    continue
  fi
  filtered_args+=("$arg")
done
set -- "${filtered_args[@]}"
echo "Filtered args: $@"

snakemake \
  --configfile ${CONFIG_FILE} \
  --snakefile ${PIPELINE}/workflow/Snakefile \
  --use-conda \
  --rerun-incomplete \
  --keep-going \
  --printshellcmds \
    $@