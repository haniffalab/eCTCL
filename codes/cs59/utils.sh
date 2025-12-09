#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Utilities for the project.
# created: 2025-06-03 Tue 15:57:38 BST
# updated: 2025-12-09
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

if [[ -z "$(command -v logger_info)" ]]; then
  logger_info () { logger -t "INFO [$(basename "$0"):$LINENO]" -s "$@"; }
fi

# Set up environment handling variables
# mamba, conda, uv, etc.
if [[ ! -z "$(command -v mamba)" ]]; then
  logger_info "Using mamba as the package manager"
  PKG_MAN="mamba"
elif [[ ! -z "$(command -v conda)" ]]; then
  logger_info "Using conda as the package manager"
  PKG_MAN="conda"
elif [[ ! -z "$(command -v uv)" ]]; then
  PKG_MAN="uv"
elif [[ ! -z "$(command -v poetry)" ]]; then
  logger_info "Using poetry as the package manager"
  PKG_MAN="poetry"
fi
echo "$(printf '@%.0s' {1..20}) ${PKG_MAN} $(printf '@%.0s' {1..20})"

function on_error () {
  local line="$1"
  local cmd="$2"
  local code="$3"
  logger_info "❌ [ERROR] Line $line: Command '$cmd' exited with status $code"
  exit "$code"
}

function on_exit () {
  local code=$?
  if [ "$code" -eq 0 ]; then
    logger_info "✅ [DONE] Script completed successfully."
  fi
}

function secret_vars () {
  # This function is used to extract hidden variables from a file.
  grep -E "^${1}:" ${2} | awk -F':' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

function secret_path () {
  # If interactive, return the full path
  if [[ $- == *i* ]]; then
    echo "${1}"
  else
    echo "${1}" | sed 's|.*'"${2:-${USER}}"'|...|'
  fi
}

function path_project () {
  # Get the directory of the current project/script
  if [[ ! -z "${1}" ]]; then cd $(dirname ${1}); fi
  local SCRIPT_LOC
  if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
      SCRIPT_LOC="$(git rev-parse --show-toplevel 2>/dev/null)"
  else
      SCRIPT_LOC="$([ -z "${PS1}" ] && echo $(realpath $(dirname $0)) || echo $(pwd))"
  fi
  if [[ ! -z "${1}" ]]; then cd - > /dev/null; fi
  echo "${SCRIPT_LOC}"
}

function file_sync () {
  if [[ $1 == "original" ]]; then
    local P0="${2}"
    local PT1="$(echo ${2} | sed 's|'"${USER}"'||g; s/codes/code/g')"
    local P1="${HOME}/${PT1}"
  else
    local P1="${1}"
    local PT1="$(echo ${1} | sed 's|'"${USER}"'||g; s/codes/code/g')"
    local P0="${2:-${HOME}/${PT1}}"
  fi
  echo "Syncing file from '${P0}' to '${P1}'"
  if [[ ! -f ${P0} ]]; then
    echo "🔹 Skipping file_sync: source file '${P0}' not found." >&2
    return 0
  fi # copy if source is newer than ${P1} (destination) or ${P1} does not exist
  if [[ "${P0}" -nt "${P1}" ]] || [[ ! -f ${P1} ]]; then
    TEMP=$(mktemp); touch -d"-2min" ${TEMP}
    if [[ -f "${P1}" ]]; then diff --unified=0 "${P1}" "${P0}"; fi
    if [[ ! -d $(dirname "${P1}") ]]; then
      echo "🔹 Skipping file_sync: '$(dirname "${P1}")' does not exist." >&2
      return 0
    fi
    cmp -s "${P0}" "${P1}" && echo "Identical files, skipping." && return 0
    local SHELLOPT_E_WAS_SET=false
    if [[ "$-" == *e* ]]; then SHELLOPT_E_WAS_SET=true; set +e; fi
    read -t 20 -p "Do you want to update '${P1}'? [y/n]: " ANSWER
    $SHELLOPT_E_WAS_SET && set -e
    if [[ "${ANSWER}" =~ ^[Yy]$ ]]; then
      logger "Updating from ${P0}"
      rsync -auvh --progress "${P0}" "${P1}"
    fi
  fi
}

function file_log () {
  local FILE="${1}"
  local TRIM="$(dirname ${2:-${PWD}})/"
  realpath -s --relative-to="${TRIM}" "${FILE/%.*/}" |
    sed 's|\.\.\/||g' |  tr '/' '.'
}

function import () {
  if [[ $# -eq 0 ]]; then
    echo "Usage: import <filename> <function1> [function2 ...]" >&2
    return 1
  fi
  local FILENAME="$1"
  if [[ -z "${@:2}" ]]; then source "${FILENAME}"; return 0; fi
  for ARG in "${@:2}"; do
    local TEMP="$(mktemp).sh"
    local FUNC_NAME="${ARG}"
    awk "/$FUNC_NAME[[:space:]]*\\(\\)/ {f=1} f {print} /^}/ && f {exit}" "$FILENAME" > "${TEMP}"
    if [[ ! -s "${TEMP}" ]]; then echo "not found" >&2; return 1; fi
    eval "$(<"${TEMP}")"
  done
}
