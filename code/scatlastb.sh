#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Script cook.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-07-01 Tue 11:03:47 BST
# updated: 2025-07-15
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

PATH_BASE=$([ -z "${PS1}" ] && echo $(dirname $0) || echo code)
SOURCE_FILES=(
  "${PATH_BASE}/logger.sh"
  "${HOME}/.conda/init.sh"
  "${PATH_BASE}/utils.sh" # PKG_MAN, path_project
)
for SOURCE_FILE in ${SOURCE_FILES[@]}; do
  if [[ -f ${SOURCE_FILE} ]]; then
    TEMP="Sourcing '${SOURCE_FILE}'"
    [ $(type -t logger) == function ] && logger "${TEMP}" 60 || logger -s "${TEMP}"
    source ${SOURCE_FILE}
  fi
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
    CONFIG_FILE=$(realpath "$arg")
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