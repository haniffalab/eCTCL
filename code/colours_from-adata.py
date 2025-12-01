#!/usr/bin/env python

"""
Fetch or compute colours from anndata object.

__created__ = "2025-09-16 Tue 15:16:00 BST"
__updated__ = "2025-09-16"
__author__ = "Ciro Ramírez-Suástegui"
__affiliation__ = "The Wellcome Sanger Institute"
__email__ = "cs59@sanger.ac.uk, cramsuig@gmail.com"
"""

def parse_args_():
    """Parse command line arguments."""
    import argparse
    parser = argparse.ArgumentParser(
        description="Fetch or compute colours from anndata object.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-i", "--input", type=str,
        help="Input path.",
    )
    parser.add_argument(
        "-l", "--labels", type=str,
        help="Comma-separated list of columns to process.",
    )
    parser.add_argument(
        "-o", "--output", type=str,
        default=f"./data/metadata",
        help="Output path.",
    )
    return parser.parse_args()


def _annotation_extract_labels(adata_obs, columns):
    import pandas as pd
    logger.info(f"Extracting columns:\n{', '.join(columns)}")
    try:
        adata_obs[columns] = adata_obs[columns].astype(str)
    except Exception as e:
        logger.info(f"Possible columns:")
        print(wrap_text(", ".join(adata_obs.columns), width=100))
        logger.error(f"Error converting columns to string: {e}")
    labels_dict = {col: adata_obs[col].unique() for col in columns}
    labels_dict = dict(sorted(labels_dict.items(), key=lambda x: len(x[0]), reverse=True))
    # replace all other keys with a mapping of the first key in adata_obs columns
    for key in labels_dict.keys():
        if key != columns[0]:
            temp = adata_obs.set_index(columns[0])[key].to_dict()
            # preserve the order of the first key
            labels_dict[key] = [temp.get(i, "NA") for i in labels_dict[columns[0]]]
    
    logger.info(f"Labels extracted:")
    print({k: len(v) for k, v in labels_dict.items()})
    logger.info(f"Largest unique set: {len(labels_dict[columns[0]])}.")
    return pd.DataFrame.from_dict(labels_dict)

def mdata_colours(
    args,
    **kwargs,
):
    from pathlib import Path
    import pprint
    pp = pprint.PrettyPrinter(indent=2)
    from src.sc2sp_benchmark.code.io import load_data
    from src.sc2sp_benchmark.code.utils import wrap_text
    from scanpy.plotting._tools.scatterplots import _color_vector
    import pandas as pd
    from src.sc2sp_benchmark.code.utils import output_save_list
    from src.sc2sp_benchmark.code.utils import output_save_instance

    ## Variables ## ------------------------------------------------------------
    temp = vars(args) if not isinstance(args, dict) else args
    args = {k: v for k, v in temp.items()}
    for i in kwargs.keys():
        args[i] = kwargs[i]
    pp.pprint(args)
    output_name = Path(args["input"]).stem
    output_path = (
        Path(args["output"])
        if args.get("output", None) is not None
        else Path(args["input"]).parent
    )
    output_path = output_path / Path(output_name + "_")
    OUTPUTS = {}

    ## Loading data ## ---------------------------------------------------------
    logger.info(f"Reading data:\n{args['input']}")
    adata = load_data(args["input"])
    logger.info(wrap_text(
        adata.__str__(), subsequent_indent=" " * 10, width=130
    ))

    ## Main code ## ------------------------------------------------------------
    labels = adata.obs.columns.tolist()
    if args["labels"] is not None:
        labels = args["labels"].split(",")
    logger.info(f"Processing columns:\n{', '.join(labels)}")
    for label in labels:
        if label not in adata.obs.columns.tolist():
            raise ValueError(f"Column '{label}' not found in AnnData object.")
        color_vector, color_type = _color_vector(
            adata=adata,
            values_key=label,
            values=adata.obs[label].values,
            palette=None,
            na_color="lightgray",
        )
        label_df = pd.DataFrame(
            {
                "value": adata.obs[label].values,
                "colour": color_vector,
            }
        )
        OUTPUTS[f"{label}_colour"] = _annotation_extract_labels(
            label_df, ["value", "colour"]
        )

    ## Saving ## ---------------------------------------------------------------
    output_save_list(
        OUTPUT_DICT=OUTPUTS,
        output_resu=str(output_path),
        number_prefix=False,
    )

def is_interactive():
    import sys
    try:
        # Works in IPython / Jupyter
        from IPython import get_ipython
        if get_ipython() is not None:
            return True
    except ImportError:
        pass
    # Fallback: regular Python REPL has sys.ps1
    return hasattr(sys, "ps1") or sys.flags.interactive

if __name__ == "__main__" and not is_interactive():
    try:
        import project_logger as logger
    except ImportError:
        try:
            import logger
        except ImportError:
            import logging
            logger = logging.getLogger(__name__)
            logging.basicConfig(level=logging.INFO)

    if is_interactive():
        with open("code/colours_from-adata.py") as f:
            exec(f.read())
    args = parse_args_()
    if is_interactive():
        args.input = "data/processed/ruoyan_2024_suspension.h5ad"
        args.labels = "cell_type"

    logger.info("Starting metadata colours.")
    mdata_colours(args)
    logger.info("Run completed successfully.")
