#!/usr/bin/env bash
# scripts/run_preprocess.sh
#
# Main entry point for preprocessing pipeline

set -euo pipefail
IFS=$'\n\t'

# ===== Resolve script location =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== Source dependencies =====
source "$SCRIPT_DIR/folder_scripts.sh"
source "$SCRIPT_DIR/pre_process.sh"

# ===== Logging helpers =====
log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# ===== Dependency checks =====
check_dependencies() {
  log "Checking dependencies..."

  command -v immv >/dev/null 2>&1 || die "immv not found (install renameutils)"
  command -v bet >/dev/null 2>&1 || die "FSL (bet) not found"
  command -v fslmaths >/dev/null 2>&1 || die "FSL (fslmaths) not found"
  command -v fsl_prepare_fieldmap >/dev/null 2>&1 || die "FSL (fsl_prepare_fieldmap) not found"

  log "All dependencies found"
}

# ===== Usage =====
usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/data [--include sub-01 sub-02 ...] [--exclude sub-09 sub-10 ...]

Description:
  Run full preprocessing pipeline on subject folders (sub-*).

Options:
  --include   Process ONLY specified subjects
  --exclude   Skip specified subjects
  -h, --help  Show this message

Notes:
  - Provide only folder names (e.g., sub-01), not full paths
  - If both --include and --exclude are given, --include takes precedence

Examples:
  $(basename "$0") /data/study
  $(basename "$0") /data/study --include sub-01 sub-03
  $(basename "$0") /data/study --exclude sub-09
EOF
}

# ===== Parse arguments =====
[[ $# -lt 1 ]] && { usage; exit 1; }

DATA_PATH="$1"
shift || true

[[ -d "$DATA_PATH" ]] || die "Path does not exist: $DATA_PATH"

include_folders=()
exclude_folders=()
mode=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include)
      mode="include"
      shift
      continue
      ;;
    --exclude)
      mode="exclude"
      shift
      continue
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ "$mode" == "include" ]]; then
        include_folders+=("$1")
      elif [[ "$mode" == "exclude" ]]; then
        exclude_folders+=("$1")
      else
        die "Unexpected argument without --include or --exclude: $1"
      fi
      ;;
  esac
  shift
done

log "Data path: $DATA_PATH"

if ((${#include_folders[@]} > 0)); then
  log "Including only: ${include_folders[*]}"
elif ((${#exclude_folders[@]} > 0)); then
  log "Excluding: ${exclude_folders[*]}"
else
  log "Processing all subjects"
fi

# ===== Check dependencies =====
check_dependencies

# ===== Get subject folders =====
readarray -t folders_array < <(list_folders "$DATA_PATH")

filtered_folders=()

if ((${#include_folders[@]} > 0)); then
  for folder in "${folders_array[@]}"; do
    name="$(basename "$folder")"
    for want in "${include_folders[@]}"; do
      [[ "$name" == "$want" ]] && filtered_folders+=("$folder")
    done
  done
else
  for folder in "${folders_array[@]}"; do
    name="$(basename "$folder")"
    skip=false
    for ex in "${exclude_folders[@]}"; do
      [[ "$name" == "$ex" ]] && skip=true && break
    done
    ! $skip && filtered_folders+=("$folder")
  done
fi

# ===== Validate result =====
if [[ ${#filtered_folders[@]} -eq 0 ]]; then
  die "No folders to process after filtering"
fi

log "Subjects to process:"
printf '  - %s\n' "${filtered_folders[@]}"

# ===== Run pipeline =====
log "Starting preprocessing pipeline"

create_training_folders "${filtered_folders[@]}"
create_subfolders "${filtered_folders[@]}"
move_files_from_f3t "${filtered_folders[@]}"
move_files_from_2022_021 "${filtered_folders[@]}"
delete_folders "${filtered_folders[@]}"
rename_and_move_edf_and_mat_files "${filtered_folders[@]}"
create_derivatives_structure "${filtered_folders[@]}"

fmap_files_process "${filtered_folders[@]}"
t1_files_process "${filtered_folders[@]}"
rename_twix_file "${filtered_folders[@]}"
prf_files_process "${filtered_folders[@]}"
resting_files_process "${filtered_folders[@]}"
move_remaining_files "${filtered_folders[@]}"

log "Pipeline completed successfully"