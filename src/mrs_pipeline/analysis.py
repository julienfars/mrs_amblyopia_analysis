"""analysis.py

Analysis utilities for the MRS pipeline.

This module contains the final quantification / fitting stage that runs
fsl_mrs on preprocessed data, using basis sets and tissue masks produced by the
preprocessing steps.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Iterable, Optional

from .utils import ensure_dir, iter_subject_session_dirs, require_command, run_command

LOGGER = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

def _locate_single_file(folder: Path, predicate) -> Optional[Path]:
    """Return the first file in a folder that matches a predicate."""
    for path in sorted(folder.iterdir()):
        if path.is_file() and predicate(path.name):
            return path
    return None


def _resolve_preproc_folder(derivatives_folder: Path, region: str, off: bool) -> Path:
    """Resolve the preprocessing output directory for a given region."""
    # Keep this flexible because older outputs may use different names.
    candidates = [
        derivatives_folder / region / "MRS_preproc_data",
        derivatives_folder / region / "MRS_preproc_data_M1",
        derivatives_folder / region / "MRS_preproc_data_V1",
        derivatives_folder / region / "output_edit_0",
        derivatives_folder / region / "output_diff",
    ]

    if off:
        candidates = [
            derivatives_folder / region / "output_edit_0",
            derivatives_folder / region / "MRS_preproc_data",
            derivatives_folder / region / "MRS_preproc_data_M1",
            derivatives_folder / region / "MRS_preproc_data_V1",
            derivatives_folder / region / "output_diff",
        ]

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]


# -----------------------------------------------------------------------------
# Main analysis
# -----------------------------------------------------------------------------

def mrs_analysis_process(
    folder: str | Path,
    basis_sets_dir: str | Path,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
    *,
    off: bool = False,
    output_prefix: str = "output",
    internal_ref: str = "NAA",
    baseline_order: int = -1,
) -> None:
    """Run fsl_mrs quantification on preprocessed edited MRS data.

    Parameters
    ----------
    folder:
        Root data directory containing sub-* folders.
    basis_sets_dir:
        Directory containing the basis set folders used by fsl_mrs.
    include / exclude:
        Optional subject filters. If include is provided, only matching subjects
        are processed.
    off:
        If True, prefer edit-off outputs where both edit conditions are present.
    output_prefix:
        Prefix used for output folders under each subject/session/region.
    internal_ref:
        Internal reference metabolite passed to fsl_mrs.
    baseline_order:
        Baseline polynomial order passed to fsl_mrs.
    """
    require_command("fsl_mrs")

    root = Path(folder)
    basis_sets_dir = Path(basis_sets_dir)

    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")
    if not basis_sets_dir.exists():
        raise FileNotFoundError(f"Basis sets directory does not exist: {basis_sets_dir}")

    basis_set_folders = {
        "diff.nii.gz": basis_sets_dir / "diff",
        "edit_1.nii.gz": basis_sets_dir / "on",
        "edit_0.nii.gz": basis_sets_dir / "off_updated",
    }

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = root / "derivatives" / "mrs" / subj_path.name / ses_path.name / "mrs"
        if not derivatives_folder.exists():
            LOGGER.info("No derivatives folder found: %s", derivatives_folder)
            continue

        LOGGER.info("Processing %s / %s", subj_path.name, ses_path.name)

        anat_folder = _locate_single_file(derivatives_folder, lambda n: n.endswith(".anat"))
        if anat_folder is None:
            LOGGER.warning("No .anat folder found in %s", derivatives_folder)
            continue

        t1_file = anat_folder / "T1.nii.gz"
        if not t1_file.exists():
            LOGGER.warning("T1 file not found in %s", anat_folder)
            continue

        # Region-specific inputs from preprocessing.
        region_specs = {
            "M1": {
                "mask": derivatives_folder / "MRS_fit_M1_mask.nii.gz",
                "seg": derivatives_folder / "MRS_fit_M1_segmentation.json",
                "out_dir": derivatives_folder / "M1" / f"{output_prefix}_diff",
            },
            "V1": {
                "mask": derivatives_folder / "MRS_fit_V1_mask.nii.gz",
                "seg": derivatives_folder / "MRS_fit_V1_segmentation.json",
                "out_dir": derivatives_folder / "V1" / f"{output_prefix}_diff",
            },
        }

        for region, spec in region_specs.items():
            preproc_folder = _resolve_preproc_folder(derivatives_folder, region, off=off)
            if not preproc_folder.exists():
                LOGGER.warning("Preproc folder not found for %s: %s", region, preproc_folder)
                continue

            wref_file = preproc_folder / "wref.nii.gz"
            if not wref_file.exists():
                LOGGER.warning("Reference water file not found: %s", wref_file)
                continue

            if not spec["mask"].exists() or not spec["seg"].exists():
                LOGGER.warning("Missing mask or segmentation for %s in %s", region, derivatives_folder)
                continue

            preproc_files = {
                "diff.nii.gz": preproc_folder / "diff.nii.gz",
                "edit_0.nii.gz": preproc_folder / "edit_0.nii.gz",
                "edit_1.nii.gz": preproc_folder / "edit_1.nii.gz",
            }

            missing = [name for name, path in preproc_files.items() if not path.exists()]
            if missing:
                LOGGER.warning("Missing preproc files for %s in %s: %s", region, preproc_folder, ", ".join(missing))
                continue

            # Mirror the original analysis logic, but make the command explicit.
            for file_suffix, preproc_file in preproc_files.items():
                basis_set_folder = basis_set_folders[file_suffix]
                if not basis_set_folder.exists():
                    LOGGER.warning("Missing basis set folder: %s", basis_set_folder)
                    continue

                out_dir = spec["out_dir"] / file_suffix.replace(".nii.gz", "")
                ensure_dir(out_dir)

                command = [
                    "fsl_mrs",
                    "--data", str(preproc_file),
                    "--h2o", str(wref_file),
                    "--tissue", str(spec["seg"]),
                    "--t1", str(t1_file),
                    "--basis", str(basis_set_folder),
                    "--internal_ref", internal_ref,
                    "--baseline_order", str(baseline_order),
                    "--output", str(out_dir),
                    "--overwrite",
                    "--report",
                ]

                if file_suffix == "edit_1.nii.gz":
                    command += [
                        "--metab_groups", "sysMM",
                        "--keep", "Ala", "Asc", "Asp", "Cr", "GABA", "GPC", "GSH", "Gln", "Glu", "Ins", "Lac", "NAAG", "NAA", "PCh", "PCr", "PE", "Scyllo", "Tau", "sysMM",
                        "--combine", "Glu", "Gln", "GSH",
                        "--combine", "GABA", "sysMM",
                        "--combine", "NAA", "NAAG",
                        "--combine", "Cr", "PCr",
                    ]
                elif file_suffix == "edit_0.nii.gz":
                    command += [
                        "--metab_groups", "MM09", "MM12", "MM14", "MM17", "MM21",
                        "--keep", "Ala", "Asc", "Asp", "Cr", "GABA", "GPC", "GSH", "Gln", "Glu", "Ins", "Lac", "NAAG", "NAA", "PCh", "PCr", "PE", "Scyllo", "Tau", "MM09", "MM12", "MM14", "MM17", "MM21",
                        "--combine", "Glu", "Gln", "GSH",
                        "--combine", "GABA", "MM09", "MM12", "MM14", "MM17", "MM21",
                        "--combine", "NAA", "NAAG",
                        "--combine", "Cr", "PCr",
                    ]
                elif file_suffix == "diff.nii.gz":
                    command += [
                        "--metab_groups", "sysMM",
                        "--keep", "GABA", "GSH", "Glu", "Gln", "NAA", "NAAG", "sysMM",
                        "--combine", "Glu", "Gln", "GSH",
                        "--combine", "GABA", "sysMM",
                        "--combine", "NAA", "NAAG",
                    ]

                run_command(command)
                LOGGER.info(
                    "Processed %s in %s using basis set %s",
                    file_suffix,
                    preproc_folder,
                    basis_set_folder,
                )


# -----------------------------------------------------------------------------
# Compatibility helper
# -----------------------------------------------------------------------------

def process_anatomical_file(anat_file: str | Path, derivatives_folder: str | Path) -> Path:
    """Kept here only for backwards compatibility if callers import from analysis.

    Prefer the preprocessing module for anatomical processing.
    """
    raise NotImplementedError(
        "process_anatomical_file belongs in preprocessing.py, not analysis.py."
    )
