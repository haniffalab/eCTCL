#!/usr/bin/env python

# ------------------------------------------------------------------------------
# purpose: Extracting obs from object and write CSV to be used independently.
# created: 2025-10-13 Mon 22:48:57 BST
# updated: 2025-10-13
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

from src.sc2sp_benchmark.code.io import load_data
from src.sc2sp_benchmark.code.tree import expand_df
import pandas as pd

adata_path = "data/processed/suspension_ruoyan_2024_ctcl.h5ad"
tree_path = "results/xenium_CTCL_scAtlasTb/ann_tree.csv"

# Getting obs
obs_df = load_data(adata_path, element="obs")
obs_df.head(10)
obs_df["cell_name"] = obs_df.index.tolist()
obs_df.rename(columns={"donor": "donor_id", "study": "study_id"}, inplace=True)
obs_df["study_id"].value_counts()

# Getting tree and expand
tree_df = pd.read_csv(tree_path, index_col=0)
obs_out = expand_df(obs_df, tree_df, verbose=1)
print(obs_out.head(10))

# temp = ["cell_name", "study_id", "donor_id", "cell_type", "ann_broad"]
obs_out.to_csv("data/processed/suspension_ruoyan_2024_ctcl_ann.csv")