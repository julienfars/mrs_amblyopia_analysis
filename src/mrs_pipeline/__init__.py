"""
mrs_pipeline

Top-level package for the MRS analysis pipeline.

This file exposes the most commonly used functions so they can be imported
directly from the package, for example:

    from mrs_pipeline import preproc, mrs_analysis_process
"""

from .utils import (
    configure_logging,
    ensure_dir,
    iter_subject_session_dirs,
    require_command,
    run_command,
    subject_is_selected,
)

from .io import (
    extract_tissue_fractions,
    process_qc_files,
    process_summary_files,
    process_tissue_fraction_files,
)

from .preprocessing import (
    MRS_anat_process,
    glance_from_derivatives,
    preproc,
    process_anatomical_file,
    process_files_with_spec2nii,
    svs_segment_process,
)

from .analysis import (
    mrs_analysis_process,
)

__all__ = [
    # utils
    "configure_logging",
    "ensure_dir",
    "iter_subject_session_dirs",
    "require_command",
    "run_command",
    "subject_is_selected",
    # io
    "extract_tissue_fractions",
    "process_qc_files",
    "process_summary_files",
    "process_tissue_fraction_files",
    # preprocessing
    "MRS_anat_process",
    "glance_from_derivatives",
    "preproc",
    "process_anatomical_file",
    "process_files_with_spec2nii",
    "svs_segment_process",
    # analysis
    "mrs_analysis_process",
]