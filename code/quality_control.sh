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
RNAME=20241115__150035__SGP206_run1
SNAMES=$(ls data/${RNAME}/)

# Run QC aggregation of Ranger results
Rscript code/spaceranger_summary.R \
  --name ${RNAME} \
  --input data/${RNAME}

## Pre-processing ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mkdir -p analysis/quality_control
mkdir -p code/quality_control

## Main ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for SNAME in ${SNAMES[@]}; do
  NNAME=${SNAME/*35__/}
  NNAME=${NNAME/__20*/}
  echo -e "=============== \033[0;32m${NNAME}\033[0m"
  EXECF=code/quality_control/${NNAME}.sh
  NBIN=analysis/qc_template.ipynb
  NBOUT=analysis/quality_control/${NNAME}.ipynb
  if [[ -f ${WORKDIR}/../logs/QC_${NNAME}.err ]]; then
    rm ${WORKDIR}/../logs/QC_${NNAME}* # remove previous logs
    rm ${NBOUT} # remove previous QC
  fi
  echo  "#!/usr/bin/env bash" > ${EXECF}
  echo  "" >> ${EXECF}
  echo  "if [[ ~/.conda/init.sh ]]; then" >> ${EXECF}
  echo  "  . ~/.conda/init.sh" >> ${EXECF}
  echo  "fi" >> ${EXECF}
  echo  "mamba activate squidpy_v1.4.1" >> ${EXECF}
  echo  "papermill ${NBIN} ${NBOUT} -p indata_name \"${NNAME}\"" >> ${EXECF}
  chmod +x ${EXECF}
  bsub -G team298 \
    -o ${WORKDIR}/../logs/QC_${NNAME}.log \
    -e ${WORKDIR}/../logs/QC_${NNAME}.err \
    -Is -n1 -q normal \
    -R "select[mem>8000] rusage[mem=8000]" -M8000 \
    -W7:30 -J "QC_${NNAME}" ${EXECF} &
done


## Conclusions ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
## Save ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

