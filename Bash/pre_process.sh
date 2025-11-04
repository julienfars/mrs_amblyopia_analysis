#!/bin/bash
# scripts.sh

fmap_files_process() {
  local folders_list=("$@")
  echo "Processing fmap files"

  for folder in "${folders_list[@]}"; do
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"
    local subjnum=$(basename "$folder")

    process_fmap_folder() {
      local training_folder=$1
      local session_label=$(basename "$training_folder")

      if [ ! -d "$training_folder" ]; then
        echo "Folder $training_folder does not exist. Skipping..."
        return
      fi

      local fmap_folder="${training_folder}/fmap"
      mkdir -p "$fmap_folder"

      shopt -s nullglob

      # Process magnitude1 (e1) files
      for file in "${training_folder}"/*fieldmap*e1*; do
        [ -e "$file" ] || continue
        if [[ "$file" == *.nii ]]; then
          immv "$file" "${fmap_folder}/${subjnum}_${session_label}_magnitude1.nii.gz"
        elif [[ "$file" == *.json ]]; then
          mv "$file" "${fmap_folder}/${subjnum}_${session_label}_magnitude1.json"
        fi
      done
      echo "fmap e1 done"

      # Process phasediff files (e2 + ph)
      for file in "${training_folder}"/*fieldmap*e2*ph*; do
        [ -e "$file" ] || continue
        if [[ "$file" == *.nii ]]; then
          immv "$file" "${fmap_folder}/${subjnum}_${session_label}_phasediff.nii.gz"
        elif [[ "$file" == *.json ]]; then
          mv "$file" "${fmap_folder}/${subjnum}_${session_label}_phasediff.json"
        fi
      done
      echo "fmap phase done"

      # Process magnitude2 (e2 but not ph)
      for file in "${training_folder}"/*fieldmap*e2*; do
        [[ "$file" == *ph* ]] && continue
        [ -e "$file" ] || continue

        if [[ "$file" == *.nii ]]; then
          immv "$file" "${fmap_folder}/${subjnum}_${session_label}_magnitude2.nii.gz"
          bet "${fmap_folder}/${subjnum}_${session_label}_magnitude2.nii.gz" \
              "${fmap_folder}/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
          fslmaths "${fmap_folder}/${subjnum}_${session_label}_magnitude2-brain.nii.gz" \
              -kernel boxv 3.8 -ero "${fmap_folder}/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
        elif [[ "$file" == *.json ]]; then
          mv "$file" "${fmap_folder}/${subjnum}_${session_label}_magnitude2.json"
        fi
      done

      # Prepare fieldmap (SIEMENS)
      local phase_file="${fmap_folder}/${subjnum}_${session_label}_phasediff.nii.gz"
      local mag_brain_file="${fmap_folder}/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
      local rads_file="${fmap_folder}/${subjnum}_${session_label}_rads.nii.gz"

      if [[ -f "$phase_file" && -f "$mag_brain_file" ]]; then
        fsl_prepare_fieldmap SIEMENS "$phase_file" "$mag_brain_file" "$rads_file" 2.46
      else
        echo "Required files for fsl_prepare_fieldmap not found in $training_folder"
      fi
    }

    # Process pre-training and post-training folders
    process_fmap_folder "$pretraining_folder"
    process_fmap_folder "$posttraining_folder"
  done
}


t1_files_process() {
  local folders_list=("$@")
  echo "Processing T1/T2 files"

  for folder in "${folders_list[@]}"; do
    local base_folder=$(basename "$folder")
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"
    local subjnum=$(basename "$folder")

    echo "Starting $base_folder"

    process_t1_folder() {
      local training_folder=$1
      local session_label=$(basename "$training_folder")

      if [ ! -d "$training_folder" ]; then
        echo "Folder $training_folder does not exist. Skipping..."
        return
      fi

      local anat_folder="${training_folder}/anat"
      mkdir -p "$anat_folder"

      shopt -s nullglob

      # T1w files
      for file in "${training_folder}"/*t1*; do
        [ -e "$file" ] || continue
        if [[ "$file" == *.nii ]]; then
          immv "$file" "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T1w.nii.gz"
          bet "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T1w.nii.gz" \
              "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T1w_brain.nii.gz"
        elif [[ "$file" == *.json ]]; then
          mv "$file" "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T1w.json"
        fi
      done
      echo "Anat T1 processed for: $training_folder"

      # T2w files
      for file in "${training_folder}"/*t2*; do
        [ -e "$file" ] || continue
        if [[ "$file" == *.nii ]]; then
          immv "$file" "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T2w.nii.gz"
          bet "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T2w.nii.gz" \
              "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T2w_brain.nii.gz"
        elif [[ "$file" == *.json ]]; then
          mv "$file" "${anat_folder}/${subjnum}_${session_label}_acq-MP2RAGE_T2w.json"
        fi
      done
      echo "Anat T2 processed for: $training_folder"
    }

    # Process both sessions
    process_t1_folder "$pretraining_folder"
    process_t1_folder "$posttraining_folder"
  done
}


# Function to process pRF task files
rename_twix_file() {
  local folders_list=("$@")
  echo "Processing MRS files..."

  for folder in "${folders_list[@]}"; do
    local subjnum
    subjnum=$(basename "$folder")
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"

    process_mrs_folder() {
      local training_folder=$1
      local session_label
      session_label=$(basename "$training_folder")

      if [ ! -d "$training_folder" ]; then
        echo "Folder $training_folder does not exist. Skipping..."
        return
      fi

      local mrs_folder="${training_folder}/mrs"
      mkdir -p "$mrs_folder"

      shopt -s nullglob  # Prevent wildcard from returning itself if no match

      for voxel in V1 M1; do
        for file in "${mrs_folder}"/*${voxel}*; do
          [[ -f "$file" ]] || continue
          local new_name=""

          case "$file" in
            *_lw_*)                new_name="${subjnum}_${session_label}_linewidth_run-${voxel}.dat" ;;
            *_fa_Cal_*)           new_name="${subjnum}_${session_label}_flip_angle_calibration_run-${voxel}.dat" ;;
            *mega_press_TR1500*)  new_name="${subjnum}_${session_label}_task-mega-press_acq-metab_run-${voxel}.dat" ;;
            *mega_press_wref1*)   new_name="${subjnum}_${session_label}_task-mega-press_acq-wref-comb-raw_run-${voxel}.dat" ;;
            *mega_press_wref3*)   new_name="${subjnum}_${session_label}_task-mega-press_acq-wref-quant-raw_run-${voxel}.dat" ;;
            *.png)                new_name="${subjnum}_${session_label}_voxel-position_run-${voxel}.png" ;;
            *) continue ;;
          esac

          mv "$file" "${mrs_folder}/${new_name}"
        done
        echo "Renamed MRS files for ${voxel} - ${subjnum} ${session_label}"
      done
    }

    process_mrs_folder "$pretraining_folder"
    process_mrs_folder "$posttraining_folder"
  done
}

prf_files_process() {
  local folders_list=("$@")
  echo "Processing pRF task files..."

  for folder in "${folders_list[@]}"; do
    local subjnum
    subjnum=$(basename "$folder")
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"

    process_prf_folder() {
      local training_folder=$1
      local session_label=$(basename "$training_folder")
      local func_folder="${training_folder}/func"
      mkdir -p "$func_folder"

      shopt -s nullglob  # Avoid wildcards expanding to themselves

      for side_label in Left Right; do
        for i in {1..4}; do
          mapfile -t prf_file_list < <(find "$training_folder" -maxdepth 1 -type f -iname "*${side_label,,}_${i}*")
          local nii_files=()
          local json_files=()

          for file in "${prf_file_list[@]}"; do
            [[ -f "$file" ]] || continue
            [[ "$file" == *.nii* ]] && nii_files+=("$file")
            [[ "$file" == *.json ]] && json_files+=("$file")
          done

          # Rename NIfTI files
          if [ ${#nii_files[@]} -ge 2 ]; then
            immv "${nii_files[0]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold_ref.nii.gz"
            immv "${nii_files[1]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.nii.gz"
          elif [ ${#nii_files[@]} -eq 1 ]; then
            immv "${nii_files[0]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.nii.gz"
          fi
          echo "pRF NIfTI files: ${subjnum} run-${i} ${side_label} done"

          # Rename JSON files
          if [ ${#json_files[@]} -ge 2 ]; then
            mv "${json_files[0]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold_ref.json"
            mv "${json_files[1]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.json"
          elif [ ${#json_files[@]} -eq 1 ]; then
            mv "${json_files[0]}" "${func_folder}/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.json"
          fi
          echo "pRF JSON files: ${subjnum} run-${i} ${side_label} done"
        done
      done
      echo "Finished processing pRF files in $training_folder"
    }

    process_prf_folder "$pretraining_folder"
    process_prf_folder "$posttraining_folder"
  done
}


resting_files_process() {
  local folders_list=("$@")
  echo "Processing resting state fMRI files..."

  for folder in "${folders_list[@]}"; do
    local subjnum
    subjnum=$(basename "$folder")
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"

    process_rest_folder() {
      local training_folder=$1
      local session_label
      session_label=$(basename "$training_folder")

      local rest_folder="${training_folder}/rest"
      mkdir -p "$rest_folder"

      shopt -s nullglob  # avoid literal wildcards

      local rest_file_list=("${training_folder}"/*resting*)
      local nii_files=()
      local json_files=()

      for file in "${rest_file_list[@]}"; do
        [[ -f "$file" ]] || continue
        [[ "$file" == *.nii* ]] && nii_files+=("$file")
        [[ "$file" == *.json ]] && json_files+=("$file")
      done

      # Rename NIfTI files
      if [ ${#nii_files[@]} -ge 2 ]; then
        immv "${nii_files[0]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold_ref.nii.gz"
        immv "${nii_files[1]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold.nii.gz"
      elif [ ${#nii_files[@]} -eq 1 ]; then
        immv "${nii_files[0]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold.nii.gz"
      fi
      echo "Resting State $subjnum $session_label NIfTI files done"

      # Rename JSON files
      if [ ${#json_files[@]} -ge 2 ]; then
        mv "${json_files[0]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold_ref.json"
        mv "${json_files[1]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold.json"
      elif [ ${#json_files[@]} -eq 1 ]; then
        mv "${json_files[0]}" "${rest_folder}/${subjnum}_${session_label}_task-rest_bold.json"
      fi
      echo "Resting State $subjnum $session_label JSON files done"
    }

    process_rest_folder "$pretraining_folder"
    process_rest_folder "$posttraining_folder"
  done
}


move_remaining_files() {
  local folders_list=("$@")
  echo "Moving extra files..."

  for folder in "${folders_list[@]}"; do
    local pretraining_folder="${folder}ses-1"
    local posttraining_folder="${folder}ses-2"

    move_remaining_files_process() {
      local training_folder=$1
      local extra_folder="${training_folder}/other"
      mkdir -p "$extra_folder"

      # Find files in root of training folder excluding known subfolders
      find "$training_folder" -maxdepth 1 -type f ! -path "$extra_folder/*" -exec mv {} "$extra_folder" \;

      # Report moved files
      local moved_files
      moved_files=$(find "$extra_folder" -type f)
      if [[ -n "$moved_files" ]]; then
        echo "Moved files to $extra_folder:"
        echo "$moved_files"
      else
        echo "No extra files found in $training_folder."
      fi
    }

    move_remaining_files_process "$pretraining_folder"
    move_remaining_files_process "$posttraining_folder"
  done
}
