#!/bin/bash

# Usage: ./rename_prf_files.sh /path/to/top/folder

# Check if path is given
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/top/folder"
    exit 1
fi

FOLDER="$1"

# Recursively find files ending with .json or .nii.gz
find "$FOLDER" -type f \( -name "*.json" -o -name "*.nii.gz" \) | while read -r FILE; do

    # Extract directory and filename
    DIR=$(dirname "$FILE")
    BASENAME=$(basename "$FILE")

    # Use regex to match and rename
    if [[ "$BASENAME" =~ ^(sub-[^_]+)_(ses-[^_]+)_task-([0-9]+)_run-([A-Za-z]+)_bold(_ref)?\.(json|nii\.gz)$ ]]; then #    if [[ "$BASENAME" =~ ^(sub-[^_]+)_(ses-[^_]+)_task-([A-Za-z]+)_run-([0-9]+)_bold(_ref)?\.(json|nii\.gz)$ ]]; then
        SUBJ="${BASH_REMATCH[1]}"
        SES="${BASH_REMATCH[2]}"
        RUN="${BASH_REMATCH[3]}"
        SIDE="${BASH_REMATCH[4],,}"  # Lowercase side
        REF="${BASH_REMATCH[5]}"    # Might be empty
        EXT="${BASH_REMATCH[6]}"

        NEW_NAME="${SUBJ}_${SES}_task-${SIDE}_run-${RUN}_bold${REF}.${EXT}"
        NEW_PATH="${DIR}/${NEW_NAME}"

        echo "Renaming:"
        echo "  $FILE"
        echo "    --> $NEW_PATH"
        mv "$FILE" "$NEW_PATH"
    fi
done
