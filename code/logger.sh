#/usr/bin/env bash

function logger() {
    if [[ -z "${1}" ]]; then
        printf "Usage: logger <message> [total_length, def:80] "
        printf "[padding_character, def:'#'] [log_type, def:INFO]\n"
        return 1
    fi
    if [[ -z "${4}" ]]; then LOGTYPE="\033[1;32mINFO\033[0m"; else LOGTYPE="${4}"; fi
    PNAME="$(git rev-parse --show-toplevel 2>&1)"
    [ ! -z "(echo ${PNAME} | grep -q fatal)" ] && PNAME="$(basename $(pwd)) "
    LOGLINE="[$(date '+%Y-%m-%d %T')] ${PNAME}${LOGTYPE} "
    LOGLINE="${LOGLINE}[${0##*/}:${FUNCNAME}:${BASH_LINENO}]"
    TEXT="${LOGLINE} :: ${1}" # echo -e "${LOGLINE} :: $*"
    echo -en "${TEXT} " # can stop here if you don't want to add padding
    TOTAL_LENGTH=${2:-80}
    if [[ -z "${3}" ]]; then PAD_CHAR="#" ; else PAD_CHAR="${3}" ; fi
    TEXT_ALONE=$(echo ${1} | sed -E 's/.*[0-9]{2}m//g; s/.033\[0m//g')
    PAD_LENGTH=$((TOTAL_LENGTH - ${#TEXT_ALONE} - 1))
    if [[ ${PAD_LENGTH} -gt 0 ]]; then
      printf "%*s" ${PAD_LENGTH} "" | tr ' ' "${PAD_CHAR}";
    fi
    echo
}

function logger_warn() {
    logger "${1}" "${2:-60}" "${3:-#}" "\033[1;33mWARN\033[0m"
}
function logger_error() {
    logger "${1}" "${2:-60}" "${3:-#}" "\033[1;31mERROR\033[0m"
}
function logger_debug() {
    logger "${1}" "${2:-60}" "${3:-#}" "\033[1;34mDEBUG\033[0m"
}
