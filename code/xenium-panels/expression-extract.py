#!/usr/bin/env python

"""
Extracting expression across panels.

__created__ = "2025-08-18 Mon 17:10:58 BST"
__updated__ = "2025-08-18"
__author__ = "Ciro Ramírez-Suástegui"
__affiliation__ = "The Wellcome Sanger Institute"
__email__ = "cs59@sanger.ac.uk, cramsuig@gmail.com"
"""

def parse_args():
    """Parse command line arguments."""
    import argparse
    parser = argparse.ArgumentParser(
        description="Measuring expression across panels.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-i", "--input", type=str,
        help="Input file path containing the overlaps between panels.",
    )
    parser.add_argument(
        "-a", "--adata", type=str,
        help="Path to AnnData object(s).",
    )
    parser.add_argument(
        "-l", "--labels", type=str,
        help="Column names in AnnData object to fetch, comma-separated.",
    )
    parser.add_argument(
        "-x", "--exclude", type=str,
        help="Pattern to exclude columns in AnnData object.",
    )
    parser.add_argument(
        "-o", "--output", type=str,
        help="Output file path.",
    )
    return parser.parse_args()

def panel_fetch_expression(args, **kwargs):
    """Fetch expression overlaps across panels."""
    from pathlib import Path
    import pandas as pd
    from src.sc2sp_benchmark.code.io import load_data
    from src.sc2sp_benchmark.code.utils import wrap_text

    ## Variables ## ------------------------------------------------------------
    temp = vars(args) if not isinstance(args, dict) else args
    args = {k: v for k, v in temp.items()}
    for i in kwargs.keys():
        args[i] = kwargs[i]
    dataset_name = Path(args["adata"]).stem
    output_dir = (
        Path(args["output"])
        if args.get("output", None) is not None
        else Path(args["input"]).parent
    )
    output_dir = output_dir / dataset_name

    ## Loading data ## ---------------------------------------------------------
    logger.info(f"Reading overlap data:\n{args['input']}")
    panel_df = pd.read_csv(args["input"])
    print(", ".join(panel_df.columns.tolist()))
    logger.info(f"Reading AnnData object(s):\n{args['adata']}")
    adata = load_data(args["adata"])
    logger.info(wrap_text(
        adata.__str__(), subsequent_indent=" " * 10, width=130
    ))

    ## Main code ## ------------------------------------------------------------
    labels = adata.obs.columns.tolist()
    if args["labels"] is not None:
        labels = args["labels"].split(",")
    if args["exclude"] is not None:
        logger.info(f"Removing columns based on '{args['exclude']}'")
        labels = [i for i in labels if args["exclude"] not in i]
        logger.info(", ".join(labels))
    aedata_list = [adata.obs.loc[:, labels].copy()]
    for panel_overlap in panel_df.columns:
        if "~" not in panel_overlap:
            logger.warning(f"Skipping '{panel_overlap}' (not an overlap)")
            continue
        logger.info(f"Processing overlap: '{panel_overlap}'")
        panel_overlap_features = list(
            set(panel_df[panel_overlap].dropna()) & set(adata.var_names)
        )
        if len(panel_overlap_features) == 0:
            logger.warning(f"Features '{panel_overlap}' not in object")
            continue
        adata_temp = adata[:, panel_overlap_features].to_memory()
        temp = pd.DataFrame(
            adata_temp.X.toarray(),
            index=adata_temp.obs_names,
            columns=panel_overlap_features,
        )
        aedata_list.append(temp)

    logger.info("Concatenating genes and labels")
    aedata_df = pd.concat(aedata_list, axis=1)

    logger.info(f"Saving data to {output_dir}.csv") ## -------------------------
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    aedata_df.to_csv(f"{output_dir}.csv", index=True)

if __name__ == "__main__":
    try:
        import project_logger as logger
    except ImportError:
        import logger
    except ImportError:
        import logging
        logger = logging.getLogger(__name__)
        logging.basicConfig(level=logging.INFO)

    args = parse_args()
    
    logger.info("Starting panel fetch expression.")
    panel_fetch_expression(args)
    logger.info("Run completed successfully.")
