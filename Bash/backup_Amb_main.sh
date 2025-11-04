#!/bin/bash
# Amb_main.sh

# Juju Fars - Main script to process Amblyopia Adult study data
# 2024/07/11

# needed for the functions 
module add fsl

# Source the functions scripts
source "$(dirname "$0")/folder_scripts.sh" # basic scripts to process the folders 
source "$(dirname "$0")/pre_process.sh" # basic preprocessing scripts for the MRI files

# DEBUG COMMANDS
# set -e  # Exit immediately if a command exits with a non-zero status.
# set -v  # Print shell input lines as they are read.
# set -x  # Print commands and their arguments as they are executed.

echo "The script for pre-preprocessing all the data is starting"

# Define the path where you want to list the directories
path_to_search="/vols/Scratch/pfr545/Amb_project/test_mrs/safety"

# List and filter folders
folders=$(list_folders "$path_to_search") 
echo "$folders"

if [ $? -ne 0 ]; then
  echo "No folders found to process."
  exit 1
fi

# Filter folders that do not contain 'ses-1' and 'ses-2' subfolders
folders=$(filter_folders "$path_to_search") 

# Print filtered folders
echo "Filtered folders:"
for folder in $folders; do
  echo "$folder"
done


## folder_script part

# Create training folders if they do not exist
create_training_folders "$folders" # will create ses-1 and ses-2

# Create necessary subfolders within each folder
create_subfolders "$folders" # will create anat, fmap, func, etc...

# Move files from 'f3t' directory to appropriate locations
move_files_from_f3t "$folders"

# Move files from '2022_021_XXX' folders to 'mrs' subfolder
move_files_from_2022_021 "$folders"

# Delete empty 'f3t' and '2022_021_XXX' folders after the files were moved
delete_folders "$folders" 

# Rename and move .edf and .mat files to the func folder
rename_and_move_edf_and_mat_files "$folders"

# creates derivatives folder and all the sub-directories of the listed participants
create_derivatives_structure "$folders"


## preprocess part

# Process field map files
fmap_files_process "$folders" # corrected 

# Process T1 and T2-weighted files
t1_files_process "$folders"

# Process MRS files 
rename_twix_file "$folders"

# Process PRF (Population Receptive Field) files
prf_files_process "$folders"

# Process resting state files
resting_files_process "$folders"

# Move unprocessed files 
move_remaining_files "$folders"
