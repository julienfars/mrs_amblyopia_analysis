"""
Input/output utilities for the MRS pipeline.

This module contains functions for:
- collecting results across subjects
- reading CSV outputs
- extracting metadata (e.g., tissue fractions)
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Optional

import pandas as pd

from .utils import iter_subject_session_dirs

LOGGER = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Summary + QC aggregation
# -----------------------------------------------------------------------------

def _collect_csv_files(
    folder: str | Path,
    filename: str,
    subfolder: str,
    off: bool = False,
) -> list[pd.DataFrame]:
    """
    Internal helper to collect CSV files across subjects.

    Parameters
    ----------
    folder:
        Root data directory.
    filename:
        Name of CSV file to collect (e.g., "summary.csv", "qc.csv").
    subfolder:
        Subfolder name (e.g., "output_diff" or "output_edit_0").
    off:
        Whether to use edit-off outputs.

    Returns
    -------
    list[pd.DataFrame]
    """
    root = Path(folder)
    all_data: list[pd.DataFrame] = []

    target_subfolder = "output_edit_0" if off else "output_diff"

    for subj_path, ses_path in iter_subject_session_dirs(root):
        for region in ("M1", "V1"):
            csv_path = (
                root
                / "derivatives"
                / "mrs"
                / subj_path.name
                / ses_path.name
                / "mrs"
                / region
                / target_subfolder
                / filename
            )

            if not csv_path.exists():
                continue

            LOGGER.info("Found %s", csv_path)

            df = pd.read_csv(csv_path)
            df["participant_number"] = subj_path.name.split("-")[-1]
            df["session"] = "pre" if ses_path.name == "ses-1" else "post"
            df["location"] = region

            all_data.append(df)

    return all_data


def process_summary_files(folder: str | Path, off: bool = False) -> Optional[pd.DataFrame]:
    """
    Combine summary.csv files across subjects.

    Returns
    -------
    DataFrame or None
    """
    data = _collect_csv_files(folder, "summary.csv", "output_diff", off)

    if not data:
        LOGGER.info("No summary.csv files found.")
        return None

    combined_df = pd.concat(data, ignore_index=True)

    out_name = "combined_summary_edit_off.csv" if off else "combined_summary_diff.csv"
    out_path = Path(folder) / "derivatives" / "mrs" / out_name

    combined_df.to_csv(out_path, index=False)
    LOGGER.info("Saved combined summary to %s", out_path)

    return combined_df


def process_qc_files(folder: str | Path, off: bool = False) -> Optional[pd.DataFrame]:
    """
    Combine qc.csv files across subjects.

    Returns
    -------
    DataFrame or None
    """
    data = _collect_csv_files(folder, "qc.csv", "output_diff", off)

    if not data:
        LOGGER.info("No qc.csv files found.")
        return None

    combined_df = pd.concat(data, ignore_index=True)

    out_name = "combined_qc_edit_off.csv" if off else "combined_qc_diff.csv"
    out_path = Path(folder) / "derivatives" / "mrs" / out_name

    combined_df.to_csv(out_path, index=False)
    LOGGER.info("Saved combined QC data to %s", out_path)

    return combined_df


# -----------------------------------------------------------------------------
# Tissue fraction extraction
# -----------------------------------------------------------------------------

def extract_tissue_fractions(file_path: str | Path) -> Optional[dict[str, float]]:
    """
    Extract CSF/GM/WM fractions from options.txt.

    Parameters
    ----------
    file_path:
        Path to options.txt file.

    Returns
    -------
    dict or None
    """
    content = Path(file_path).read_text(encoding="utf-8")

    pattern = r'"tissue_frac": \{"CSF": (\d+\.?\d*), "GM": (\d+\.?\d*), "WM": (\d+\.?\d*)\}'
    match = re.search(pattern, content)

    if not match:
        return None

    return {
        "CSF": float(match.group(1)),
        "GM": float(match.group(2)),
        "WM": float(match.group(3)),
    }


def process_tissue_fraction_files(folder: str | Path) -> Optional[pd.DataFrame]:
    """
    Collect tissue fraction data across subjects and save as CSV.
    """
    root = Path(folder)
    all_data: list[pd.DataFrame] = []

    for subj_path, ses_path in iter_subject_session_dirs(root):
        for region in ("M1", "V1"):
            option_file = (
                root
                / "derivatives"
                / "mrs"
                / subj_path.name
                / ses_path.name
                / "mrs"
                / region
                / "output_diff"
                / "options.txt"
            )

            if not option_file.exists():
                continue

            tissue_data = extract_tissue_fractions(option_file)

            if tissue_data is None:
                continue

            df = pd.DataFrame([{
                "participant_number": subj_path.name.split("-")[-1],
                "session": "pre" if ses_path.name == "ses-1" else "post",
                "location": region,
                "CSF": tissue_data["CSF"],
                "GM": tissue_data["GM"],
                "WM": tissue_data["WM"],
            }])

            all_data.append(df)

    if not all_data:
        LOGGER.info("No tissue fraction data found.")
        return None

    combined_df = pd.concat(all_data, ignore_index=True)

    out_path = root / "derivatives" / "mrs" / "combined_tissue_fraction.csv"
    combined_df.to_csv(out_path, index=False)

    LOGGER.info("Saved tissue fraction data to %s", out_path)

    return combined_df