#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# __title: Utilities for the project.
# created: 2025-06-03 Tue 15:57:38 BST
# updated: 2025-06-03
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

# Set up environment handling variables
# mamba, conda, uv, etc.
if [[ ! -z "$(command -v mamba)" ]]; then
  PKG_MAN="mamba"
elif [[ ! -z "$(command -v conda)" ]]; then
  PKG_MAN="conda"
elif [[ ! -z "$(command -v uv)" ]]; then
  PKG_MAN="uv"
fi

function hidden_vars() {
  # This function is used to extract hidden variables from a file.
  # grep -E "^${1}:" ${2} | sed -E "s/${1}:(.*)/\1/" | tr -d '[:space:]'
  grep -E "^${1}:" ${2} | awk '{print $2}' | tr -d '[:space:]'
}

function path_project() {
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
