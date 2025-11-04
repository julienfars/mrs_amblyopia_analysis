#!/bin/bash

# Example usage:
# bash run_mrs_analysis_fslsub.sh /home/fs0/pfr545/scratch/Amb_project/test_data '["sub-01", "sub-09"]' 1

# Load conda and activate environment
source ~/.bashrc
conda activate fsl_mrs_env  # Change if your environment has a different name

# Full path to Python in conda env (update if needed)
PYTHON_EXECUTABLE="/home/fs0/pfr545/anaconda3/envs/fsl_mrs_env/bin/python"

# Input arguments
DATA_PATH="$1"
EXCLUDE="$2"     # e.g. '["sub-01", "sub-09"]'
PHASE_CORR="$3"  # e.g. 1 (set anything to enable, leave empty to disable)

# fsl_sub settings
QUEUE="short"
TIME_LIMIT="300"  # in minutes (recommended: 600)
MEMORY="32"       # in GB (recommended: 64)
SLOTS="8"         # number of CPU cores (recommended: 8)
PYTHON_SCRIPT="run_mrs_analysis.py"

# Construct base command
CMD=("$PYTHON_EXECUTABLE" "$PYTHON_SCRIPT" "--data" "$DATA_PATH")

# Add exclude_list if provided
if [ -n "$EXCLUDE" ]; then
  CMD+=("--exclude_list" "$EXCLUDE")
fi

# Add --phase_corr flag if provided
if [ -n "$PHASE_CORR" ]; then
  CMD+=("--phase_corr")
fi

# Submit with fsl_sub
fsl_sub \
  -q "$QUEUE" \
  -T "$TIME_LIMIT" \
  -R "$MEMORY" \
  -s "$SLOTS" \
  "${CMD[@]}"

# Echo command summary
echo "Submitted MRS job with the following parameters:"
echo "  Data path:         $DATA_PATH"
echo "  Excluded subjects: ${EXCLUDE:-None}"
echo "  Phase correction:  ${PHASE_CORR:-Disabled}"
