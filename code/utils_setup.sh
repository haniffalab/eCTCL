#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Utilities for the setting up projects.
# created: 2025-08-17 Sun 14:16:01 BST
# updated: 2025-08-17
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

function setup_env_fetch_src () {
  logger_info "Creating/referencing to software directory" 0 >&2
  if [[ -d "/software/cellgen" ]]; then
    logger_info "Using CellGen's software directory" 0 >&2
    # export TEMP="$(realpath "${1}" | sed 's/.*team/team/g')"
    export PATH_SOFTWARE="/software/cellgen/$(id -gn)/${USER}"
  else
    logger_info "Using local software directory" 0 >&2
    mkdir ${HOME}/software
    # export TEMP="$(echo "${1}" | sed 's/.*group/group/g')"
    export PATH_SOFTWARE="${HOME}/software"
  fi

  logger_info "Source directory: ${PATH_SOFTWARE}" 0 >&2
  [ ! -d "${PATH_SOFTWARE}" ] && mkdir "${PATH_SOFTWARE}"
  echo "${PATH_SOFTWARE}"
}

function setup_env_fetch_repos () {
  local PATH_SOURCE=$(setup_env_fetch_src "${1:-${PWD}}")
  if [[ $# -eq 0 ]]; then logger_error "No repositories provided." 0; fi
  local -n GIT_REPOS_REF="${2:-GIT_REPOS}"
  for ENV_NAME in ${!GIT_REPOS_REF[@]}; do
    REPO_NAME="$(basename "${GIT_REPOS_REF[${ENV_NAME}]}" .git)"
    logger_info "Setting up '${ENV_NAME}' from '${REPO_NAME}'" 60 "-"
    if [[ "${REPO_NAME}" =~ \.(yaml|yml)$ ]]; then
      logger_warn "Skipping YAML file" 0
      continue
    fi
    REPO_PATHS=()
    PATH_FIND=(ls -d ${HOME}/group*)
    PATH_FIND+=("${PATH_SOURCE}")
    while read -r GROUP_DIR; do # search in group directories and src
      # logger_info "Searching for '${REPO_NAME}' in '${GROUP_DIR}'" 0
      REPO_PATH_="${GROUP_DIR}/${REPO_NAME}"
      if [[ -d "${REPO_PATH_}" ]] || [[ -L "${REPO_PATH_}" ]]; then
        # logger_info "Found repository in '${REPO_PATH_}'" 0
        REPO_PATHS+=("${REPO_PATH_}")
      fi
    done < <("${PATH_FIND[@]}")
    # Picking the repository path with the most recent modification
    if [[ ${#REPO_PATHS[@]} -eq 0 ]]; then
      REPO_PATH="${PATH_SOURCE}/${REPO_NAME}"
    else
      logger_info "Found repositories:" 0; echo "${REPO_PATHS[@]}"
      REPO_PATH=$(
        printf "%s\n" "${REPO_PATHS[@]}" |
        xargs -I {} stat --format="%Y %n" {} |
        sort -n | tail -n 1 | awk '{print $2}'
      )
    fi
    logger_info "Using repository path: '${REPO_PATH}'" 0
    if [[ ! -d "${REPO_PATH}" ]]; then
      logger_info "Cloning repository '$(basename ${REPO_PATH})'" 0
      git clone "${GIT_REPOS_REF[${ENV_NAME}]}" "${REPO_PATH}"
    fi
    if [[ ! -L "${1}/src/${REPO_NAME}" ]]; then
      logger_info "Linking repository '${REPO_NAME}' to src" 0
      ln -s "${REPO_PATH}" "${1}/src/${REPO_NAME}"
    else
      logger_info "Repository '${REPO_NAME}' already linked to src" 0
    fi
    REPO_PATH="$(realpath ${REPO_PATH})"
    # Linking environment files to the envs directory
    ENV_REMOTE="${REPO_PATH}/envs/${ENV_NAME}.yaml"
    ENV_LOCALY="${1}/envs/${ENV_NAME}.yaml"
    if [[ ! -f "${ENV_REMOTE}" ]] && [[ ! -f "${ENV_LOCALY}" ]]; then
      logger_warn "No environment file, will pip install instead" 0
      echo "# pip install -e ${REPO_PATH} --quiet" > "${ENV_LOCALY}"
      echo "name: ${ENV_NAME}" >> "${ENV_LOCALY}"
      echo "channels:" >> "${ENV_LOCALY}"
      echo "  - conda-forge" >> "${ENV_LOCALY}"
      echo "dependencies:" >> "${ENV_LOCALY}"
      echo "  - python" >> "${ENV_LOCALY}"
      echo "  - pip" >> "${ENV_LOCALY}"
      # echo "    pip:" >> "${ENV_LOCALY}"
      # TEMP="$(
      #   echo "${GIT_REPOS_REF[${ENV_NAME}]}" | sed 's|^git|git+https://| s|:|/|'
      # )@main"
      # echo "      - ${TEMP}" >> "${ENV_LOCALY}"
    fi
    # if file is not linked nor exists, link it
    if [[ ! -f "${ENV_LOCALY}" ]]; then
      ln -s "${ENV_REMOTE}" "${ENV_LOCALY}"
    fi
  done
}

function setup_env_create () {
  while read -r ENV_FILE; do
    ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
    ENV_LOG="$(echo "${ENV_FILE/%.*/}" | sed 's|'"${1}/"'||' | tr '/' '.')"
    ENV_LOG=".logs/${ENV_LOG}_$(date +%Y%m%d)"
    logger "'${ENV_NAME}' from '${ENV_FILE}'" 0
    if ${PKG_MAN} env list 2>/dev/null | grep -q " ${ENV_NAME} "; then
      logger_warn "Environment '${ENV_NAME}' already exists, skipping." 0
      continue
    fi
    echo "Logging to: '${ENV_LOG}'"
    {
      logger_info "[START] - ${ENV_NAME}"
      ${PKG_MAN} env create -y --file "${ENV_FILE}" --name "${ENV_NAME}"
      logger_info "[END] - ${ENV_NAME}"
    } 2>&1 | tee "${ENV_LOG}"
    if grep -q "pip install" "${ENV_FILE}"; then
      logger_info "Installing environment '${ENV_NAME}' using pip" 0
      TEMP="$(grep -E "pip install" "${ENV_FILE}" | awk '{print $5}')"
      logger_info "Location: '${TEMP}'" 0
      [ -d "${TEMP}" ] && {
        ${PKG_MAN} activate "${ENV_NAME}"
        pip install -e "${TEMP}" --quiet 2>&1
      } 2>&1 | tee -a "${ENV_LOG}"
    fi
  done < <(find ${1}/envs/ -name "*.yaml")
}

function setup_env_add_kernels () {
  while read -r ENV_FILE; do
    ENV_NAME=$(grep -E "^name:" "${ENV_FILE}" | awk '{print $2}')
    if jupyter kernelspec list | grep -q " ${ENV_NAME} "; then
      logger_warn "Kernel '${ENV_NAME}' already exists, skipping." 0
    else
      logger_info "Adding kernel '${ENV_NAME}'" 0
      ${PKG_MAN} activate "${ENV_NAME}"
      if [[ "$(${PKG_MAN} list | grep "^ipykernel" | wc -l)" -eq 0 ]]; then
        ${PKG_MAN} install -y ipykernel --quiet
      fi
      python -m ipykernel install --user --name "${ENV_NAME}" \
        --display-name "${ENV_NAME}" --user
    fi
  done < <(find "${1}/envs/" -name "*.yaml")
}

function download_data () {
  if [[ -z "$(command -v wget)" ]]; then
    curl "${1}" --silent --output "${2}"
  else
    wget "${1}" --quiet --output-document "${2}"
  fi
}

function path_find_up () {
  local pattern="$1"
  local dir="${2:-$(pwd)}"
  while [[ "$dir" != "/" ]]; do
    for entry in "$dir"/*; do
      if [[ -d "$entry" && "$(basename "$entry")" == *"$pattern"* ]]; then
        echo "$entry"
        return 0
      fi
    done
    dir=$(dirname "$dir")
  done
  return 1  # Not found
}


function str_is_sim () {
  dist=$(
    python -c "import Levenshtein;\
    print(Levenshtein.distance('${1^^}', '${2^^}'))"
  )
  if [[ $dist -lt 3 ]]; then
    echo "${2}"
  fi
}

function setup_data_copy () {
  local -n PATH_SUBSETS="${1}"
  local PATH_COPY="${2:-data/raw}"
  local PATTERN="${3:-*output-*}"
  local INCLUDE="${4:-.*}" # regex to include samples
  local EXCLUDE="${5:-nothing2excludehere}" # regex to exclude samples
  shift 2 # Parse named options
  while [[ $# -gt 0 ]]; do
      case $1 in
          --pattern) PATTERN="${2}"; shift 2 ;;
          --include) INCLUDE="${2}"; shift 2 ;;
          --exclude) EXCLUDE="${2}"; shift 2 ;;
          *) echo "Unknown option: $1"; return 1 ;;
      esac
  done
  # if it does not end with an underscore, add a slash
  if [[ "${PATH_COPY}" != *_ ]]; then PATH_COPY="${PATH_COPY%/}/"; fi
  for PATH_SUBSET_I in "${!PATH_SUBSETS[@]}"; do
    PATH_SUBSET="${PATH_SUBSETS[${PATH_SUBSET_I}]}"
    logger_info "'${PATH_SUBSET_I}' - '$(basename "${PATH_SUBSET}")'" 60 "-"
    CCOUNT=0; DCOUNT=0
    mkdir -p "${PATH_COPY}${PATH_SUBSET_I}"
    mapfile -t PATH_FIND < <(
      find "${PATH_SUBSET}" -maxdepth 2 -name "${PATTERN}" -type d |
      grep -E "${INCLUDE}" | grep -vE "${EXCLUDE}"
    )
    while read -r PATH_SAMPLE; do
      DCOUNT=$(($DCOUNT + 1))
      SAMPLE_NAME="$(
        basename "${PATH_SAMPLE}" | sed -E 's/__[0-9]{8}.*//; s/.*__//'
      )" # remove extension and date
      printf " * '${SAMPLE_NAME}'"
      echo " < '$(basename "${PATH_SAMPLE}")'"
      PATH_COPY_I="${PATH_COPY}${PATH_SUBSET_I}/${SAMPLE_NAME}"
      # if it can't be accessed from a node during a job, we need to make a copy
      mkdir -p "${PATH_COPY_I}"
      rsync -auvh --progress \
        --exclude "analysis" --exclude "aux_outputs" --exclude "*.html" \
        --exclude "aux_outputs" --exclude "analysis" \
        --exclude "cell_feature_matrix" --exclude "morphology_focus" \
        "${PATH_SAMPLE/%\//}" "${PATH_COPY_I}/"
      CCOUNT=$(($CCOUNT + 1))
    done < <(printf '%s\n' "${PATH_FIND[@]}")
    printf "${CCOUNT}/${DCOUNT} copied\n"
}

function setup_data_copy_he () {
    local -n PATH_SUBSETS="${1}"
    local PATH_COPY="${2:-data/raw}"
    # Fetching the H&E data from upstream 'Post Xenium H&E' directory
    PATH_HE="$(path_find_up "Post" "${PATH_SUBSET}")"
    if [[ -z "${PATH_HE}" ]]; then
      PATH_HE="$(path_find_up "H&E" "${PATH_SUBSET}")"
    fi
    if [[ -z "${PATH_HE}" ]]; then
      logger_warn "No H&E images found" 0
      continue
    else
      logger_info "Copying H&E images" 0
      echo "$(secret_path "${PATH_HE}")"
    fi
    CCOUNT=0; DCOUNT=0
    mapfile -t PATH_FIND < <(
      find "${PATH_HE}" -name "*ndpi" -type f | grep -vE "${EXCLUDE}"
    )
    while read -r PATH_IMAGE; do
      DCOUNT=$(($DCOUNT + 1))
      IMAGE_NAME="$(basename "${PATH_IMAGE}")"
      SAMPLE_NAME="$(
        echo ${IMAGE_NAME%%.*} |
        sed -E 's/- *[0-9]{4,}.*//; s/_[A-Z][0-9] .*//; s/.*_//; s/.* - //' |
        tr -d ' '
      )" # remove extension
      PATH_COPY_I="${PATH_COPY}${PATH_SUBSET_I}/${SAMPLE_NAME}"
      if [[ ! -d "${PATH_COPY_I}" ]]; then
        # finding the right sample name folder
        for SAMPLE_I in "${PATH_COPY}${PATH_SUBSET_I}"/*; do
          TEMP="${SAMPLE_I##*/}"
          if [[ "${SAMPLE_NAME^^}" == "${TEMP^^}" ]]; then
            PATH_COPY_I="${SAMPLE_I}"; SAMPLE_NAME="${SAMPLE_I##*/}"; color="32"
            break
          fi
          if [[ "${SAMPLE_NAME^^}" == *${TEMP^^}* ]] ||
             [[ "${TEMP^^}" == *${SAMPLE_NAME^^}* ]]; then
            PATH_COPY_I="${SAMPLE_I}"
            SAMPLE_NAME_PUTATIVE="${SAMPLE_I##*/}"
            color="33" # yellow
          fi
        done
        if [[ -z "${color}" ]]; then
          for SAMPLE_I in "${PATH_COPY}${PATH_SUBSET_I}"/*; do
            TEMP="${SAMPLE_I##*/}"
            SAMPLE_NAME_PUTATIVE="$(str_is_sim "${SAMPLE_NAME}" "${TEMP}")"
            if [[ -n "${SAMPLE_NAME_PUTATIVE}" ]]; then
              PATH_COPY_I="${SAMPLE_I}"
              SAMPLE_NAME="${SAMPLE_NAME_PUTATIVE}"
              color="34"; break # blue
            fi
          done
        fi
      fi
      [[ -d "${PATH_COPY_I}" && -n "${color}" ]] || color="31"
      if [[ "${color}" != "32" ]] && [[ -n "${SAMPLE_NAME_PUTATIVE}" ]]; then
        SAMPLE_NAME="${SAMPLE_NAME_PUTATIVE}"
      fi
      printf " \033[1;${color}m*\033[0m '${SAMPLE_NAME}'";
      echo -e " \033[0;${color}m<\033[0m '${IMAGE_NAME}'"
      # print in green if the sample name is found
      CMD="rsync -auvh --progress \"${PATH_IMAGE}\" \"${PATH_COPY_I}/\""
      if [[ "${color}" == "34" ]]; then
        echo "$(echo ${CMD} | sed 's| "| \\\n "|g')"
        continue
      fi
      if [[ ! -d "${PATH_COPY_I}" ]]; then continue; fi
      # eval "${CMD}"
      unset SAMPLE_NAME; unset SAMPLE_NAME_PUTATIVE
      CCOUNT=$(($CCOUNT + 1)); unset color;
    done < <(printf '%s\n' "${PATH_FIND[@]}")
    printf "${CCOUNT}/${DCOUNT} images copied\n"
    unset CCOUNT; unset DCOUNT;
  done
}