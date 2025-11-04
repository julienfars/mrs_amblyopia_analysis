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

# ===== HANDLE INPUT ARGUMENTS =====
path_to_search="$1"
shift # Shift so the remaining args are exclusions
excluded_folders=("$@")

if [[ -z "$path_to_search" ]]; then
  echo "Error: Please provide the path to search as the first argument."
  echo "Usage: ./amb_main.sh /path/to/search sub-09 sub-10 ..."
  exit 1
fi

echo "Searching in path: $path_to_search"
echo "Excluding folders: ${excluded_folders[*]}"

# ===== LIST AND FILTER FOLDERS =====
readarray -t folders_array < <(list_folders "$path_to_search")

# Exclude specified folders (e.g., "sub-09" not full path)
filtered_folders=()
for folder in "${folders_array[@]}"; do
  folder_basename=$(basename "$folder")  # extract "sub-XX"
  skip=false
  for exclude in "${excluded_folders[@]}"; do
    if [[ "$folder_basename" == "$exclude" ]]; then
      skip=true
      break
    fi
  done
  if ! $skip; then
    filtered_folders+=("$folder")
  fi
done

# Make sure the result is not empty
if [[ "${#filtered_folders[@]}" -eq 0 ]]; then
  echo "No folders left to process after exclusions."
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
# rename_and_move_edf_and_mat_files "${filtered_folders[@]}"
create_derivatives_structure "${filtered_folders[@]}"


# fmap_files_process "${filtered_folders[@]}"
# t1_files_process "${filtered_folders[@]}"
# rename_twix_file "${filtered_folders[@]}"
# prf_files_process "${filtered_folders[@]}"
# resting_files_process "${filtered_folders[@]}"
# move_remaining_files "${filtered_folders[@]}"


echo "script is done, if you notice errors in folder architecture, remove the last / in your first argument and launch the script again"
