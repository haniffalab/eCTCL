#!/usr/bin/env bash

if [[ -f ${HOME}/.conda/init.sh ]]; then
  source ${HOME}/.conda/init.sh
fi

# Create environment
if [[ -z $(${PKG_MAN} env list | grep env_r) ]]; then
  echo "Creating environment 'env_r' with R essentials and base."
  ${PKG_MAN} create -y -n env_r -c conda-forge r-essentials r-base
else
  echo "Environment 'env_r' already exists. Skipping creation."
fi

${PKG_MAN} activate env_r

# Set up renv
Rscript -e "install.packages('renv', repos = 'https://cloud.r-project.org')"
Rscript -e "renv::init()"

# Install specific packages
# might benefit from `conda install gxx_linux-64` as it's
# needed for some packages
Rscript -e "renv::install('logging')"
Rscript -e "renv::install('tidyverse')"
Rscript -e "renv::install('optparse')"
Rscript -e "renv::install('effectsize')"