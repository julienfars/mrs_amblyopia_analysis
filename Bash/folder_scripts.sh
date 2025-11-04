#!/bin/bash
# folder_scripts.sh

#set -x

list_folders() {
  local path=$1

  # Check if the path exists
  if [ ! -d "$path" ]; then
    echo "The specified path does not exist: ${path}"
    return 1
  fi

  find "$path" -maxdepth 1 -type d -name 'sub-*' -printf "%p/\n"
}



# Function to filter out folders that already contain 'ses-1' and 'ses-2'
filter_folders() {
  local input_folders=("$@")
  local output_folders=()

  for folder in "${input_folders[@]}"; do
    if [[ -d "$folder/ses-1" && -d "$folder/ses-2" ]]; then
      echo "Skipping $folder as it contains both 'ses-1' and 'ses-2' subfolders."
    else
      output_folders+=("$folder")
    fi
  done

  # Output one folder per line (safe for readarray)
  printf "%s\n" "${output_folders[@]}"
}



# Function to filter folders by matching any of the given numbers
filter_sub() {
  local folders_to_filter=("$@")
  local numbers=("${folders_to_filter[@]: -1}")   # Last item = numbers string
  folders_to_filter=("${folders_to_filter[@]:0:${#folders_to_filter[@]}-1}")  # All but last
  local filtered=()

  IFS=' ' read -r -a number_array <<< "$numbers"  # split string to array

  for folder in "${folders_to_filter[@]}"; do
    for num in "${number_array[@]}"; do
      if [[ "$folder" == *"$num"* ]]; then
        filtered+=("$folder")
        break
      fi
    done
  done

  printf "%s\n" "${filtered[@]}"
}




# Function to check and create pretraining and posttraining folders
create_training_folders() {
  echo "Checking and creating 'pretraining' and 'posttraining' folders"

  for folder in "$@"; do
    pretraining_folder="${folder}ses-1"
    posttraining_folder="${folder}ses-2"

    if [ ! -d "$pretraining_folder" ]; then
      echo "Creating folder: $pretraining_folder"
      mkdir -p "$pretraining_folder"
    else
      echo "Folder already exists: $pretraining_folder"
    fi

    if [ ! -d "$posttraining_folder" ]; then
      echo "Creating folder: $posttraining_folder"
      mkdir -p "$posttraining_folder"
    else
      echo "Folder already exists: $posttraining_folder"
    fi
  done
}


create_subfolders() {
  echo "Checking and creating 'anat', 'fmap', 'func', 'mrs', 'other' folders inside ses-1 and ses-2"
  required_subfolders=("anat" "fmap" "func" "mrs" "other")

  for folder in "$@"; do
    pretraining_folder="${folder}ses-1"
    posttraining_folder="${folder}ses-2"

    for subfolder in "${required_subfolders[@]}"; do
      for training_folder in "$pretraining_folder" "$posttraining_folder"; do
        target="${training_folder}/${subfolder}"
        if [ ! -d "$target" ]; then
          echo "Creating folder: $target"
          mkdir -p "$target"
        else
          echo "Folder already exists: $target"
        fi
      done
    done
  done
}


# Function to move files from F3T folders
move_files_from_f3t() {
  echo "Moving files from F3T folders"

  for folder in "$@"; do
    pretraining_folder="${folder}ses-1"
    posttraining_folder="${folder}ses-2"

      # Find F3T folders safely, suppress errors if none exist
      mapfile -t f3t_folders < <(find "$folder" -maxdepth 1 -type d -name 'F3T_2022_021_*' 2>/dev/null)

      if [ "${#f3t_folders[@]}" -eq 0 ]; then
        echo "No F3T folders found in ${folder}"
        continue
      fi

      # Sort F3T folders by number suffix
      sorted_folders=($(printf "%s\n" "${f3t_folders[@]}" | sort -V))

      smallest_f3t_folder="${sorted_folders[0]}"
      largest_f3t_folder="${sorted_folders[-1]}"

      # Move files from smallest to pretraining
      if [ -n "$smallest_f3t_folder" ]; then
        echo "Moving files from $smallest_f3t_folder to $pretraining_folder"
        shopt -s nullglob
        mv "$smallest_f3t_folder"/* "$pretraining_folder" 2>/dev/null || echo "Nothing to move from $smallest_f3t_folder"
        shopt -u nullglob
      fi

      # Move files from largest to posttraining
      if [ "$largest_f3t_folder" != "$smallest_f3t_folder" ]; then
        echo "Moving files from $largest_f3t_folder to $posttraining_folder"
        shopt -s nullglob
        mv "$largest_f3t_folder"/* "$posttraining_folder" 2>/dev/null || echo "Nothing to move from $largest_f3t_folder"
        shopt -u nullglob
      fi
    
  done
}


move_files_from_2022_021() {
  echo "Moving files from '2022_021_XXX' folders to 'mrs'"

  for folder in "$@"; do
    pretraining_folder="${folder}ses-1"
    posttraining_folder="${folder}ses-2"

    process_2022_021_folder() {
      local parent_folder="$1"
      local pre="${parent_folder}ses-1/mrs"
      local post="${parent_folder}ses-2/mrs"

      mkdir -p "$pre" "$post"

      # Find folders like 2022_021_XXX inside base path (not within ses-*)
      mapfile -t matching_folders < <(find "$parent_folder" -maxdepth 1 -type d -name '2022_021_*')

      if [ "${#matching_folders[@]}" -eq 0 ]; then
        echo "No 2022_021_XXX folders found in $parent_folder"
        return
      fi

      # Sort by trailing number
      sorted=($(printf "%s\n" "${matching_folders[@]}" | sort -t'_' -k3,3n))

      if [ "${#sorted[@]}" -eq 1 ]; then
        echo "Only one 2022_021 folder, moving to $pre"
        shopt -s nullglob
        mv "${sorted[0]}"/* "$pre/" 2>/dev/null || echo "Nothing to move from ${sorted[0]}"
        shopt -u nullglob
      else
        echo "Multiple 2022_021 folders found, moving first to $pre, second to $post"
        shopt -s nullglob
        mv "${sorted[0]}"/* "$pre/" 2>/dev/null || echo "Nothing to move from ${sorted[0]}"
        mv "${sorted[1]}"/* "$post/" 2>/dev/null || echo "Nothing to move from ${sorted[1]}"
        shopt -u nullglob
      fi
    }

    process_2022_021_folder "$folder"
  done
}



delete_folders() {
  echo "Deleting empty '2022_021_XXX' and 'F3T_2022_021_YYY' folders"

  for folder in "$@"; do
    mapfile -t subfolders < <(find "$folder" -mindepth 1 -maxdepth 1 -type d)

    for subfolder in "${subfolders[@]}"; do
      base=$(basename "$subfolder")

      if [[ "$base" =~ ^[0-9]{4}_021_[0-9]+$ || "$base" =~ ^F3T_[0-9]{4}_021_[0-9]+$ ]]; then
        if [ -z "$(ls -A "$subfolder" 2>/dev/null)" ]; then
          echo "Deleting empty folder: $subfolder"
          rm -rf "$subfolder"
        else
          echo "Skipping non-empty folder: $subfolder"
          ls -1 "$subfolder"
        fi
      fi
    done
  done
}


rename_and_move_edf_and_mat_files() {
  local folders_list=("$@")  # Use array to handle folder names with spaces
  local first_folder="${folders_list[0]}"
  local base_dir
  base_dir=$(dirname "$first_folder")
  local participants_file="${base_dir}/participants.tsv"
  declare -A amblyopic_eyes

  echo "Loading amblyopic eye information from: $participants_file"

    # Read participants.tsv (tab-separated, skip header)
  while IFS=$'\t' read -r participant eye; do
    [[ "$participant" == "participant" ]] && continue
    local subj_id="${participant#sub-}"                      # remove "sub-"
    local normalized_subj_id=$(echo "$subj_id" | sed 's/^0*//')  # remove leading zeros
    amblyopic_eyes["$normalized_subj_id"]="$eye"             # use as key
  done < "$participants_file"

  echo "Renaming and moving .edf and .mat files"

  for folder in "${folders_list[@]}"; do
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"

    process_files() {
      local training_folder="$1"
      local session_label
      session_label=$(basename "$training_folder")

      if [ ! -d "$training_folder" ]; then
        echo "Folder $training_folder does not exist. Skipping..."
        return
      fi

      mkdir -p "${training_folder}/func"

      mapfile -t edf_files < <(find "$training_folder" -type f -name "*subj*_run*_exp93.edf")
      mapfile -t mat_files < <(find "$training_folder" -type f -name "*subj*_run*_exp93.mat")

      for edf_file in "${edf_files[@]}"; do
        if [[ "$edf_file" =~ _subj([0-9]+)_run([0-9]+)_exp93\.edf$ ]]; then
          local subj_num_raw="${BASH_REMATCH[1]}"
          local subj_num=$(echo "$subj_num_raw" | sed 's/^0*//')  # normalize
          local run_num_raw="${BASH_REMATCH[2]}"
          local run_num=$((10#$run_num_raw))  # strip leading zeros safely
          local eye="${amblyopic_eyes[$subj_num]}"

          if [[ -z "$eye" ]]; then
            echo "No eye info for subject $subj_num. Skipping $edf_file"
            continue
          fi

          local task_eye
          local new_run_num

          if (( run_num >= 1 && run_num <= 4 )); then
            task_eye="$eye"
            new_run_num="$run_num"
          else
            task_eye=$([[ "$eye" == "left" ]] && echo "right" || echo "left")
            new_run_num=$((run_num - 4))
          fi

          local new_name="sub-${subj_num}_${session_label}_task-${task_eye}_run-${new_run_num}_eyetracking.edf"
          mv "$edf_file" "${training_folder}/func/$new_name"
        fi
      done

      for mat_file in "${mat_files[@]}"; do
        if [[ "$mat_file" =~ _subj([0-9]+)_run([0-9]+)_exp93\.mat$ ]]; then
          local subj_num_raw="${BASH_REMATCH[1]}"
          local subj_num=$(echo "$subj_num_raw" | sed 's/^0*//')  # normalize
          local run_num_raw="${BASH_REMATCH[2]}"
          local run_num=$((10#$run_num_raw))  # strip leading zeros safely
          local eye="${amblyopic_eyes[$subj_num]}"


          if [[ -z "$eye" ]]; then
            echo "No eye info for subject $subj_num. Skipping $mat_file"
            continue
          fi

          local task_eye
          local new_run_num

          if (( run_num >= 1 && run_num <= 4 )); then
            task_eye="$eye"
            new_run_num="$run_num"
          else
            task_eye=$([[ "$eye" == "left" ]] && echo "right" || echo "left")
            new_run_num=$((run_num - 4))
          fi

          local new_name="sub-${subj_num}_${session_label}_task-${task_eye}_run-${new_run_num}_run-details.mat"
          mv "$mat_file" "${training_folder}/func/$new_name"
        fi
      done
    }

    process_files "$pretraining_folder"
    process_files "$posttraining_folder"
  done
}



create_derivatives_structure() {
  local folders_list=("$@")  # Use array to properly handle spaces
  local first_folder="${folders_list[0]}"
  local base_dir
  base_dir=$(dirname "$first_folder")
  local derivatives_dir="${base_dir}/derivatives"

  echo "Base directory detected as: $base_dir"
  echo "Creating derivatives directory structure..."

  mkdir -p "$derivatives_dir"

  for folder in "${folders_list[@]}"; do
    local subject_id
    subject_id=$(basename "$folder")
    local subject_derivatives_path="${derivatives_dir}/${subject_id}"

    if [ ! -d "$subject_derivatives_path" ]; then
      mkdir -p "$subject_derivatives_path"
      echo "Created: $subject_derivatives_path"
    else
      echo "Already exists: $subject_derivatives_path"
    fi
  done
}
