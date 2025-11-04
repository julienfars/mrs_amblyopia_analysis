#!/bin/bash
# Amb_main.sh

# Juju Fars - Main script to process Amblyopia Adult study data
# 2024/07/11

# Needed for the functions 
module add fsl

# Source the functions scripts
source "$(dirname "$0")/folder_scripts.sh"
source "$(dirname "$0")/pre_process.sh"

# DEBUG COMMANDS
# set -e
# set -v
# set -x

echo "The script for pre-preprocessing all the data is starting"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/search [--include sub-01 sub-02 ...] [--exclude sub-09 sub-10 ...]

Notes:
  - Provide exactly one of --include or --exclude. If both are provided, --include takes precedence.
  - Folder names are basenames like "sub-01" (not full paths).
Examples:
  $(basename "$0") /data/study --include sub-01 sub-03
  $(basename "$0") /data/study --exclude sub-09 sub-10
EOF
}

# ===== HANDLE INPUT ARGUMENTS =====
path_to_search="$1"
shift || true

if [[ -z "$path_to_search" ]]; then
  echo "Error: Please provide the path to search as the first argument."
  usage
  exit 1
fi

# Parse flags after the search path:
include_folders=()
exclude_folders=()
mode=""  # "", "include", or "exclude"

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
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      # Positional arg after a mode = collect folder names
      if [[ "$mode" == "include" ]]; then
        include_folders+=("$1")
      elif [[ "$mode" == "exclude" ]]; then
        exclude_folders+=("$1")
      else
        echo "Unexpected argument without a mode (--include/--exclude): $1"
        usage
        exit 1
      fi
      ;;
  esac
  shift
done

echo "Searching in path: $path_to_search"
if ((${#include_folders[@]} > 0)); then
  echo "Including ONLY folders: ${include_folders[*]}"
elif ((${#exclude_folders[@]} > 0)); then
  echo "Excluding folders: ${exclude_folders[*]}"
else
  echo "No include/exclude filters provided."
fi

# ===== LIST AND FILTER FOLDERS =====
readarray -t folders_array < <(list_folders "$path_to_search")

# If include list is provided, keep only those; else apply excludes
filtered_folders=()

if ((${#include_folders[@]} > 0)); then
  for folder in "${folders_array[@]}"; do
    folder_basename=$(basename "$folder")
    for want in "${include_folders[@]}"; do
      if [[ "$folder_basename" == "$want" ]]; then
        filtered_folders+=("$folder")
        break
      fi
    done
  done
else
  # Exclude specified folders (e.g., "sub-09" not full path)
  for folder in "${folders_array[@]}"; do
    folder_basename=$(basename "$folder")
    skip=false
    for exclude in "${exclude_folders[@]}"; do
      if [[ "$folder_basename" == "$exclude" ]]; then
        skip=true
        break
      fi
    done
    if ! $skip; then
      filtered_folders+=("$folder")
    fi
  done
fi

# Make sure the result is not empty
if [[ "${#filtered_folders[@]}" -eq 0 ]]; then
  echo "No folders left to process after filters."
  exit 1
fi

# Further filtering: keep only folders that have ses-1 and ses-2
#readarray -t filtered_folders < <(filter_folders "${filtered_folders[@]}")

# Print final folders
echo "Filtered folders:"
for folder in "${filtered_folders[@]}"; do
  echo "$folder"
done

# ====== Run the full pipeline ======
# create_training_folders "${filtered_folders[@]}"
# create_subfolders "${filtered_folders[@]}"
# move_files_from_f3t "${filtered_folders[@]}"
# move_files_from_2022_021 "${filtered_folders[@]}"
# delete_folders "${filtered_folders[@]}"
rename_and_move_edf_and_mat_files "${filtered_folders[@]}"
# create_derivatives_structure "${filtered_folders[@]}"

# fmap_files_process "${filtered_folders[@]}"
# t1_files_process "${filtered_folders[@]}"
# rename_twix_file "${filtered_folders[@]}"
prf_files_process "${filtered_folders[@]}"
# resting_files_process "${filtered_folders[@]}"
# move_remaining_files "${filtered_folders[@]}"

echo "script is done, if you notice errors in folder architecture, remove the last / in your first argument and launch the script again"
