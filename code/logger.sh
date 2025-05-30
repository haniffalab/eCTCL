#/usr/bin/env bash

# logger "Text" [total length] [padding character]
function logger() {
    PNAME="$(git rev-parse --show-toplevel 2>&1)"
    [ ! -z "(echo ${PNAME} | grep -q fatal)" ] && PNAME="$(basename $(pwd)) "
    LOGLINE="[$(date '+%Y-%m-%d %T')] ${PNAME}\033[1;32mINFO\033[0m "
    LOGLINE="${LOGLINE}[${0##*/}:${FUNCNAME}:${BASH_LINENO}]"
    TEXT="${LOGLINE} :: ${1}" # echo -e "${LOGLINE} :: $*"
    echo -en "${TEXT} " # can stop here if you don't want to add padding
    TOTAL_LENGTH=${2:-80}
    if [[ -z "${3}" ]]; then PAD_CHAR="%" ; else PAD_CHAR="${3}" ; fi
    TEXT_ALONE=$(echo ${1} | sed -E 's/.*[0-9]{2}m//g; s/.033\[0m//g')
    PAD_LENGTH=$((TOTAL_LENGTH - ${#TEXT_ALONE} - 1))
    if [[ ${PAD_LENGTH} -lt 0 ]]; then PAD_LENGTH=1; fi
    printf "%*s" ${PAD_LENGTH} "" | tr ' ' "${PAD_CHAR}";
    echo
}
