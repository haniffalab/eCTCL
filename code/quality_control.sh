#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# title: Iterative QCing of Xenium samples.
# purpose: This is script that goes through the first CTCL samples generated.
#           on 2024-08-15.
#
# created: 2024-12-03 Tue 16:34:06 GMT
# updated: 2024-12-06
# version: 0.0.9
# status: Prototype
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# Exectute: binary cook.ext 2>&1 | tee -a .logs/cook_$(date +%Y%m%d%H%M%S).log

## Environment setup ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Quick installations --------------------------------------
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
# set -e # -x
# In-house/developing --------------------------------------
# Tool (packaged) modules ----------------------------------

## Global variables and paths ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
WORKDIR="$([ -z "${PS1}" ] && echo $(realpath $(dirname $0)) || echo $(pwd))"
echo "Working at: '${WORKDIR}'"

# Run name and the samples
RNAME=20240815__115640__SGP177_SKI_run1
# RNAME=20241115__150035__SGP206_run1
SNAMES=($(ls -d data/${RNAME}/* | grep --color=never _AX))

## Pre-processing ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mkdir -p analysis/quality_control
mkdir -p code/quality_control

## Main ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for SNAME in ${SNAMES[@]}; do
  NNAME0=$(basename ${SNAME})
  # remove leading and trailing numbers
  NNAME=$(echo ${NNAME0} | sed -e 's/.*[0-9]__\([A-Z]\)\(.*\)/\1\2/g')
  NNAME=${NNAME/__*/}
  echo -e "=============== \033[0;32m${NNAME}\033[0m"
  EXECF=code/quality_control/${NNAME}.sh
  if [[ -f ${WORKDIR}/../logs/QC_${NNAME}.err ]]; then
    rm ${WORKDIR}/../logs/QC_${NNAME}* # remove previous logs
    rm ${NBOUT} # remove previous QC
  fi
  # Creating bash script to run the QC # -------------------
  echo "#!/usr/bin/env bash" > ${EXECF}
  echo "" >> ${EXECF}
  echo "if [[ ~/.conda/init.sh ]]; then" >> ${EXECF}
  echo "  . ~/.conda/init.sh" >> ${EXECF}
  echo "fi" >> ${EXECF}
  echo -e "mamba activate squidpy_v1.4.1\n" >> ${EXECF}
  echo "NBIN=analysis/qc_template.ipynb" >> ${EXECF}
  echo "NBOUT=analysis/quality_control/${NNAME}.ipynb" >> ${EXECF}
  echo "SPATH=${RNAME}/${NNAME0}" >> ${EXECF}
  echo "papermill \${NBIN} \${NBOUT} -p sample_path \"\${SPATH}\"" >> ${EXECF}
  chmod +x ${EXECF}
  bsub -G team298 \
    -o ${WORKDIR}/../logs/QC_${NNAME}_$(date '+%Y-%m-%d').out \
    -e ${WORKDIR}/../logs/QC_${NNAME}_$(date '+%Y-%m-%d').err \
    -Is -n1 -q normal \
    -R "select[mem>6000] rusage[mem=6000]" -M6000 \
    -W7:30 -J "QC_${NNAME}" ${EXECF} #&
  break
done


## Conclusions ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
## Save ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

