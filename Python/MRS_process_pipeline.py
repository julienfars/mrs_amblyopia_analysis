# MRS_process_pipeline.py

import os
import subprocess
import pandas as pd
import fsl_mrs_preproc_edit 
import re
import json
from joblib import Parallel, delayed


def process_files_with_spec2nii(folder, exclude=None, include=None):
    import os, subprocess

    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return

    exclude = exclude or []
    include = include or []

    for root, dirs, _ in os.walk(folder):
        if include:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and any(inc in d for inc in include)]
        else:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and not any(ex in d for ex in exclude)]

        for sub_dir in dirs:
            sub_path = os.path.join(root, sub_dir)
            ses_dirs = [d for d in os.listdir(sub_path) if 'ses' in d and os.path.isdir(os.path.join(sub_path, d))]

            for ses_dir in ses_dirs:
                mrs_folder = os.path.join(sub_path, ses_dir, 'mrs')
                if not os.path.exists(mrs_folder):
                    continue

                print(f"Found 'mrs' folder: {mrs_folder}")

                derivatives_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs')
                os.makedirs(derivatives_folder, exist_ok=True)

                for file in os.listdir(mrs_folder):
                    if not file.endswith('.dat'):
                        continue

                    file_path = os.path.join(mrs_folder, file)
                    base = os.path.splitext(file)[0]

                    if 'mega-press_acq-metab' in file:
                        metab_name = f"{base}_metab"
                        print(f"Processing {file_path} with spec2nii for metab")
                        subprocess.run(["spec2nii", "twix", "-e", "image", "-f", metab_name, "-o", derivatives_folder, "-j", "-q", file_path])

                        phasecorr_name = f"{base}_phase_correlated"
                        print(f"Processing {file_path} with spec2nii for phasecor")
                        subprocess.run(["spec2nii", "twix", "-e", "phasecor", "-f", phasecorr_name, "-o", derivatives_folder, "-j", "-q", file_path])

                    elif 'mega-press_acq-wref-comb-raw' in file:
                        out_name = f"{base}_wref-comb-raw"
                        print(f"Processing {file_path} with spec2nii for wref-comb-raw")
                        subprocess.run(["spec2nii", "twix", "-e", "image", "-f", out_name, "-o", derivatives_folder, "-j", "-q", file_path])

                    elif 'mega-press_acq-wref-quant-raw' in file:
                        out_name = f"{base}_wref-quant-raw"
                        print(f"Processing {file_path} with spec2nii for wref-quant-raw")
                        subprocess.run(["spec2nii", "twix", "-e", "image", "-f", out_name, "-o", derivatives_folder, "-j", "-q", file_path])



def glance_from_derivatives(folder, include=None, exclude=None):
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    if exclude is None:
        exclude = []
    
    if include is None:
        include = []

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-' and match include list if provided
        if include:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and any(inc in d for inc in include)]
            print(dirs)
        else:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and not any(ex in d for ex in exclude)]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)
            
            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]
                
                for ses_dir in sub_dirs:
                    derivatives_folder = os.path.join(folder, 'derivatives', sub_dir, ses_dir, 'mrs') # was derivatives_folder = os.path.join(sub_root, ses_dir, 'derivatives')
                    if os.path.exists(derivatives_folder):
                        print(f"Found 'derivatives' folder: {derivatives_folder}")
                        
                        # Load images within the 'derivatives' folder
                        for file in os.listdir(derivatives_folder):
                            if file.endswith('.nii.gz'):
                                file_path = os.path.join(derivatives_folder, file)
                                new_file = os.path.splitext(file_path)[0]+'.png'
                                new_txt_file = os.path.splitext(file_path)[0]+'.txt'

                                if 'metab.nii' in file:
                                    print(f"Processing {file_path} with mrs_io.read_FID for metab")
                                    subprocess.run(["mrs_tools", "vis", file_path, "--save", new_file, "--ppmlim", '0', '6.65'])
                                    subprocess.run(["mrs_tools", "info", file_path], capture_output=True, text=new_txt_file)

                                elif 'phase_correlated.nii' in file:
                                    print(f"Processing {file_path} with mrs_io.read_FID for metab")    
                                    subprocess.run(["mrs_tools", "vis", file_path, "--save", new_file, "--ppmlim", '0', '6.65'])
                                    subprocess.run(["mrs_tools", "info", file_path], capture_output=True, text=new_txt_file)
                                
                                elif 'mega-press_acq-wref-comb-raw' in file:
                                    print(f"Processing {file_path} with mrs_io.read_FID for wref-comb-raw")
                                    subprocess.run(["mrs_tools", "vis", file_path, "--save", new_file, "--ppmlim", '2.65', '6.65'])
                                    subprocess.run(["mrs_tools", "info", file_path], capture_output=True, text=new_txt_file)
                                
                                elif 'mega-press_acq-wref-quant-raw' in file:
                                    print(f"Processing {file_path} with mrs_io.read_FID for wref-quant-raw")
                                    subprocess.run(["mrs_tools", "vis", file_path, "--save", new_file, "--ppmlim", '2.65', '6.65'])
                                    subprocess.run(["mrs_tools", "info", file_path], capture_output=True, text=new_txt_file)
                    else:
                        print(f"No derivatives found for: {sub_dir} {ses_dir}")

def preproc(folder, ref_water=None, include=None, exclude=None):
    """
    Preprocess MRS data files from derivatives folders in a BIDS-like structure.

    Args:
        folder (str): Path to the root folder containing BIDS-style data and derivatives.
        ref_water (str, optional): Type of reference water file to use. 
            If 'phase_corr', uses phase-correlated metab file as reference. 
            If None, uses standard water reference files.
        include (list, optional): List of participant IDs to include (e.g., ['sub-001']).
        exclude (list, optional): List of participant IDs to exclude.
    """
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    if exclude is None:
        exclude = []
    
    if include is None:
        include = []

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-' and match include list if provided
        if include:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and any(inc in d for inc in include)]
            print(dirs)
        else:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and not any(ex in d for ex in exclude)]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)
            
            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]
                
                for ses_dir in sub_dirs:
                    derivatives_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs') # was derivatives_folder = os.path.join(sub_root, ses_dir, 'derivatives')
                    if os.path.exists(derivatives_folder):
                        print(f"Found 'derivatives' folder: {derivatives_folder}")
                        
                        # List all files in the derivatives folder
                        all_files = os.listdir(derivatives_folder)
                        
                        # Process both V1 and M1 files
                        for region in ['V1', 'M1']:
                            region_files = [f for f in all_files if region in f and f.endswith('.nii.gz')]
                            
                            if len(region_files) > 0:
                                # Find required files
                                metab_file = None
                                ref_file = None
                                quant_file = None
                                ecc_file = None 
                                
                                for file in region_files:
                                    if 'metab' in file and 'phase_correlated' not in file:
                                        metab_file = os.path.join(derivatives_folder, file)
                                    
                                    #if ref_water == 'phase_corr':
                                    if 'metab' in file and 'phase_correlated' in file:
                                        ecc_file = os.path.join(derivatives_folder, file)
                                    #else:
                                    if 'mega-press_acq-wref-comb-raw' in file:
                                        ref_file = os.path.join(derivatives_folder, file)
                                    
                                    if 'mega-press_acq-wref-quant-raw' in file:
                                        quant_file = os.path.join(derivatives_folder, file)
                                
                                # Check if the required files are found
                                if metab_file and ref_file:
                                    # Prepare the subprocess command
                                    command = [
                                        'fsl_mrs_preproc_edit',
                                        '--data', metab_file,
                                        '--reference', ref_file,
                                        '--quant', quant_file,
                                        '--output', os.path.join(derivatives_folder, f'MRS_preproc_data_{region}'),
                                        '--ecc', ecc_file, 
                                        '--hlsvd',
                                        '--report',
                                        '--overwrite',
                                        '--align_window_dynamic', '16',
                                        '--align_ppm_edit', '2.5', '3.5'
                                    ]
                                    # former commands: 
                                    # Run subprocess command
                                    subprocess.run(command)
                                    print(f"Processed {region} files in {derivatives_folder}")
                                else:
                                    print(f"Required files for {region} not found in {derivatives_folder}")
                            else:
                                print(f"No {region} files found in {derivatives_folder}")



def process_anatomical_file(anat_file, derivatives_folder):
    import os, subprocess
    """
    Function to process a single anatomical file with fsl_anat.
    """
    base_name = os.path.splitext(os.path.splitext(os.path.basename(anat_file))[0])[0]  # Remove .nii.gz
    output_path = os.path.join(derivatives_folder, f"MRS_{base_name}")
    
    subprocess.run(
        "module load fsl && fsl_anat -i {} -o {}".format(anat_file, output_path),
        shell=True,
        executable="/bin/bash"  # important: ensures it's a login shell
    )
    return f"Processed anatomical file and saved output to: {output_path}"

def MRS_anat_process(folder, use_parallel=False, n_jobs=-1, include=None, exclude=None):
    import os, subprocess
    """
    Processes anatomical files in a given folder, optionally using parallel processing with joblib.
    
    Parameters:
    - folder (str): The root directory to search for anatomical files.
    - use_parallel (bool): Whether to enable parallel processing. Default is False.
    - n_jobs (int): The number of parallel jobs to run. Default is -1 (use all available CPUs).
    """
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    tasks = []  # Collect all tasks for processing
    
    if exclude is None:
        exclude = []
    
    if include is None:
        include = []

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-' and match include list if provided
        if include:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and any(inc in d for inc in include)]
            print(dirs)
        else:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and not any(ex in d for ex in exclude)]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)
            
            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]
                
                for ses_dir in sub_dirs:
                    derivatives_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs') # was derivatives_folder = os.path.join(sub_root, ses_dir, 'derivatives')
                    anat_folder = os.path.join(sub_root, ses_dir, 'anat')
                    
                    if os.path.exists(derivatives_folder) and os.path.exists(anat_folder):
                        # Look for the specific anatomical file in the anat folder
                        for file in os.listdir(anat_folder):
                            if file.startswith('sub-') and file.endswith('_acq-MP2RAGE_T1w.nii.gz'):
                                anat_file = os.path.join(anat_folder, file)
                                tasks.append((anat_file, derivatives_folder))
    
    if use_parallel:
        # Use joblib's Parallel to process tasks in parallel
        results = Parallel(n_jobs=n_jobs)(
            delayed(process_anatomical_file)(anat_file, derivatives_folder) for anat_file, derivatives_folder in tasks
        )
        for result in results:
            print(result)
    else:
        # Process files sequentially
        for anat_file, derivatives_folder in tasks:
            result = process_anatomical_file(anat_file, derivatives_folder)
            print(result)


def svs_segment_process(folder, include=None, exclude=None):
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return

    if exclude is None:
        exclude = []

    if include is None:
        include = []

    # List sub- directories at the top level
    sub_dirs = [d for d in os.listdir(folder) if d.startswith('sub-') and os.path.isdir(os.path.join(folder, d))]

    if include:
        sub_dirs = [d for d in sub_dirs if any(inc in d for inc in include)]
    else:
        sub_dirs = [d for d in sub_dirs if not any(ex in d for ex in exclude)]

    print(f"Subjects to process: {sub_dirs}")

    for sub_dir in sub_dirs:
        sub_path = os.path.join(folder, sub_dir)

        # Look for ses-* folders inside each sub_dir
        ses_dirs = [d for d in os.listdir(sub_path) if 'ses' in d and os.path.isdir(os.path.join(sub_path, d))]

        for ses_dir in ses_dirs:
            derivatives_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs')

            if os.path.exists(derivatives_folder):
                print(f"Found 'derivatives' folder: {derivatives_folder}")

                # Look for .anat folder
                anat_folder = None
                for f in os.listdir(derivatives_folder):
                    if f.endswith('.anat'):
                        anat_folder = os.path.join(derivatives_folder, f)
                        break

                if anat_folder:
                    print(f"Found .anat folder: {anat_folder}")

                    # Look for metab files
                    v1_metab_file = None
                    m1_metab_file = None
                    for f in os.listdir(derivatives_folder):
                        if 'task-mega-press' in f:
                            if f.endswith('V1_metab.nii.gz'):
                                v1_metab_file = os.path.join(derivatives_folder, f)
                            elif f.endswith('M1_metab.nii.gz'):
                                m1_metab_file = os.path.join(derivatives_folder, f)

                    if v1_metab_file:
                        print(f"Found V1 metab file: {v1_metab_file}")
                        subprocess.run("module load fsl && svs_segment {} -a {} -o {} -f MRS_fit_V1".format(v1_metab_file, anat_folder, derivatives_folder),
                                        shell=True, executable="/bin/bash")
                        print(f"Processed SVS segmentation for V1")

                    if m1_metab_file:
                        print(f"Found M1 metab file: {m1_metab_file}")
                        subprocess.run("module load fsl && svs_segment {} -a {} -o {} -f MRS_fit_M1".format(m1_metab_file, anat_folder, derivatives_folder),
                                        shell=True, executable="/bin/bash")
                        print(f"Processed SVS segmentation for M1")

                    if not v1_metab_file:
                        print(f"No V1 metab file found in {derivatives_folder}")
                    if not m1_metab_file:
                        print(f"No M1 metab file found in {derivatives_folder}")
                else:
                    print(f"No .anat folder found in {derivatives_folder}")



def mrs_analysis_process(folder, include=None, exclude=None):
    # Define the basis sets directory and specific subfolders
    basis_sets_dir = "/home/fs0/pfr545/GitLab/win-mrs-basis-sets/basis_sets/uzay_svs_mpress/uzay_svs_mpress_68_with_db"
    basis_set_folders = {
        'diff.nii.gz': 'diff',
        'edit_1.nii.gz': 'on',
        'edit_0.nii.gz': 'off_updated'
    }

    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return

    if exclude is None:
        exclude = []

    if include is None:
        include = []

    for root, dirs, files in os.walk(folder):
        # Filter subject folders
        if include:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and any(inc in d for inc in include)]
        else:
            dirs[:] = [d for d in dirs if d.startswith('sub-') and not any(ex in d for ex in exclude)]

        for sub_dir in dirs:
            sub_path = os.path.join(root, sub_dir)

            # Filter only valid session directories
            session_dirs = [
                d for d in os.listdir(sub_path)
                if d.startswith('ses-') and os.path.isdir(os.path.join(sub_path, d))
            ]

            for ses_dir in session_dirs:
                derivatives_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs')

                if os.path.exists(derivatives_folder):
                    print(f"Found 'derivatives' folder: {derivatives_folder}")

                    # Locate .anat folder and T1 file
                    anat_folder = None
                    t1_file = None
                    for folder_name in os.listdir(derivatives_folder):
                        if folder_name.endswith('.anat'):
                            anat_folder = os.path.join(derivatives_folder, folder_name)
                            break

                    if anat_folder:
                        print(f"Found .anat folder: {anat_folder}")
                        for file in os.listdir(anat_folder):
                            if file == "T1.nii.gz":
                                t1_file = os.path.join(anat_folder, file)
                                break

                        if t1_file:
                            print(f"Found T1 file: {t1_file}")

                            # Define masks and segmentation paths
                            m1_mask_file = os.path.join(derivatives_folder, "MRS_fit_M1_mask.nii.gz")
                            m1_segmentation_file = os.path.join(derivatives_folder, "MRS_fit_M1_segmentation.json")
                            v1_mask_file = os.path.join(derivatives_folder, "MRS_fit_V1_mask.nii.gz")
                            v1_segmentation_file = os.path.join(derivatives_folder, "MRS_fit_V1_segmentation.json")

                            if not (os.path.exists(m1_mask_file) and os.path.exists(m1_segmentation_file)):
                                print(f"Required M1 files not found in {derivatives_folder}")
                                continue
                            if not (os.path.exists(v1_mask_file) and os.path.exists(v1_segmentation_file)):
                                print(f"Required V1 files not found in {derivatives_folder}")
                                continue

                            # Loop over M1 and V1 preprocessing folders
                            for preproc_folder_name in ['MRS_preproc_data_M1', 'MRS_preproc_data_V1']:
                                preproc_folder = os.path.join(derivatives_folder, preproc_folder_name)

                                if os.path.exists(preproc_folder):
                                    print(f"Found preproc folder: {preproc_folder}")
                                    wref_file = os.path.join(preproc_folder, "wref.nii.gz")

                                    preproc_files = {}
                                    for file_suffix in ['diff.nii.gz', 'edit_0.nii.gz', 'edit_1.nii.gz']:
                                        file_path = os.path.join(preproc_folder, file_suffix)
                                        if os.path.exists(file_path):
                                            preproc_files[file_suffix] = file_path
                                            print(f"Found preproc file: {file_path}")
                                        else:
                                            print(f"File {file_suffix} not found in {preproc_folder}")

                                    if all(key in preproc_files for key in ['diff.nii.gz', 'edit_0.nii.gz', 'edit_1.nii.gz']):
                                        if preproc_folder_name == 'MRS_preproc_data_M1':
                                            mask_file = m1_mask_file
                                            segmentation_file = m1_segmentation_file
                                            ext = 'M1'
                                        else:
                                            mask_file = v1_mask_file
                                            segmentation_file = v1_segmentation_file
                                            ext = 'V1'

                                        for file_suffix, preproc_file in preproc_files.items():
                                            basis_set_folder = os.path.join(basis_sets_dir, basis_set_folders[file_suffix])

                                            command = [
                                                'fsl_mrs',
                                                '--data', preproc_file,
                                                '--h2o', wref_file,
                                                '--tissue', segmentation_file,
                                                '--t1', t1_file,
                                                '--basis', basis_set_folder,
                                                '--internal_ref', 'NAA',
                                                '--baseline_order', '-1',
                                                '--output', os.path.join(derivatives_folder, ext, f'output_{file_suffix.split(".")[0]}'),
                                                '--overwrite',
                                                '--report'
                                            ]

                                            if file_suffix == 'edit_1.nii.gz':
                                                command += [
                                                    '--metab_groups', 'sysMM',
                                                    '--keep', 'Ala', 'Asc', 'Asp', 'Cr', 'GABA', 'GPC', 'GSH', 'Gln', 'Glu', 'Ins', 'Lac', 'NAAG', 'NAA', 'PCh', 'PCr', 'PE', 'Scyllo', 'Tau', 'sysMM',
                                                    '--combine', 'Glu', 'Gln', 'GSH',
                                                    '--combine', 'GABA', 'sysMM',
                                                    '--combine', 'NAA', 'NAAG',
                                                    '--combine', 'Cr', 'PCr'
                                                ]
                                            elif file_suffix == 'edit_0.nii.gz':
                                                command += [
                                                    '--metab_groups', 'MM09', 'MM12', 'MM14', 'MM17', 'MM21',
                                                    '--keep', 'Ala', 'Asc', 'Asp', 'Cr', 'GABA', 'GPC', 'GSH', 'Gln', 'Glu', 'Ins', 'Lac', 'NAAG', 'NAA', 'PCh', 'PCr', 'PE', 'Scyllo', 'Tau', 'MM09', 'MM12', 'MM14', 'MM17', 'MM21',
                                                    '--combine', 'Glu', 'Gln', 'GSH',
                                                    '--combine', 'GABA', 'MM09', 'MM12', 'MM14', 'MM17', 'MM21',
                                                    '--combine', 'NAA', 'NAAG',
                                                    '--combine', 'Cr', 'PCr'
                                                ]
                                            elif file_suffix == 'diff.nii.gz':
                                                command += [
                                                    '--metab_groups', 'sysMM',
                                                    '--keep', 'GABA', 'GSH', 'Glu', 'Gln', 'NAA', 'NAAG', 'sysMM',
                                                    '--combine', 'Glu', 'Gln', 'GSH',
                                                    '--combine', 'GABA', 'sysMM',
                                                    '--combine', 'NAA', 'NAAG'
                                                ]

                                            subprocess.run(command)
                                            print(f"Processed {file_suffix} in {preproc_folder} using basis set {basis_set_folder}")
                                else:
                                    print(f"Preproc folder {preproc_folder} not found.")
                        else:
                            print(f"T1 file not found in {anat_folder}")
                    else:
                        print(f".anat folder not found in {derivatives_folder}")

def process_summary_files(folder):
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    all_data = []
    kk_values = ['M1', 'V1']  # These are the possible values for KK

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-'
        dirs[:] = [d for d in dirs if d.startswith('sub-')]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)

            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]

                for ses_dir in sub_dirs:
                    for kk in kk_values:
                        # Construct the path to the output_diff folder for each KK value
                        output_diff_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs', kk, 'output_diff') # was output_diff_folder = os.path.join(sub_root, ses_dir, 'derivatives', kk, 'output_diff')
                        summary_file = os.path.join(output_diff_folder, 'summary.csv')

                        if os.path.exists(summary_file):
                            print(f"Found summary.csv: {summary_file}")

                            # Extract participant number, session, and location
                            participant_number = sub_dir.split('-')[-1]
                            session = 'pre' if 'ses-1' in ses_dir else 'post'
                            location = kk

                            # Read and process the summary.csv file
                            df = pd.read_csv(summary_file)
                            df['participant_number'] = participant_number
                            df['session'] = session
                            df['location'] = location

                            # Add the processed DataFrame to the list
                            all_data.append(df)

    if all_data:
        # Combine all DataFrames into one
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Save combined DataFrame to a new CSV file
        combined_csv_path = os.path.join(folder, 'derivatives', 'mrs', 'combined_summary_diff.csv')
        combined_df.to_csv(combined_csv_path, index=False)
        print(f"Combined summary data saved to {combined_csv_path}")
        #print(combined_df)
    else:
        print("No summary.csv files found.")


def process_QC_files(folder):
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    all_data = []
    kk_values = ['M1', 'V1']  # These are the possible values for KK

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-'
        dirs[:] = [d for d in dirs if d.startswith('sub-')]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)

            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]

                for ses_dir in sub_dirs:
                    for kk in kk_values:
                        # Construct the path to the output_diff folder for each KK value
                        output_diff_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs', kk, 'output_diff') # was output_diff_folder = os.path.join(sub_root, ses_dir, 'derivatives', kk, 'output_diff')
                        summary_file = os.path.join(output_diff_folder, 'qc.csv')

                        if os.path.exists(summary_file):
                            print(f"Found qc.csv: {summary_file}")

                            # Extract participant number, session, and location
                            participant_number = sub_dir.split('-')[-1]
                            session = 'pre' if 'ses-1' in ses_dir else 'post'
                            location = kk

                            # Read and process the summary.csv file
                            df = pd.read_csv(summary_file)
                            df['participant_number'] = participant_number
                            df['session'] = session
                            df['location'] = location

                            # Add the processed DataFrame to the list
                            all_data.append(df)

    if all_data:
        # Combine all DataFrames into one
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Save combined DataFrame to a new CSV file
        combined_csv_path = os.path.join(folder, 'derivatives', 'mrs', 'combined_qc_diff.csv')
        combined_df.to_csv(combined_csv_path, index=False)
        print(f"Combined qc data saved to {combined_csv_path}")
        #print(combined_df)
    else:
        print("No qc.csv files found.")


def extract_tissue_fractions(file_path):
    """Extract tissue fraction (CSF, GM, WM) from the option.txt file."""
    with open(file_path, 'r') as file:
        content = file.read()
        
    # Regex pattern to match the tissue fraction dictionary
    pattern = r'"tissue_frac": \{"CSF": (\d+\.?\d*), "GM": (\d+\.?\d*), "WM": (\d+\.?\d*)\}'
    
    # Search for the pattern in the file content
    match = re.search(pattern, content)
    
    if match:
        csf = float(match.group(1))
        gm = float(match.group(2))
        wm = float(match.group(3))
        return {"CSF": csf, "GM": gm, "WM": wm}
    else:
        return None
        
    
def process_tissue_fraction_files(folder):
    # Check if the directory exists
    if not os.path.exists(folder):
        print(f"The folder {folder} does not exist.")
        return
    
    all_data = []
    kk_values = ['M1', 'V1']  # These are the possible values for KK

    # Walk through the directory recursively
    for root, dirs, files in os.walk(folder):
        # Filter dirs to only include folders that start with 'sub-'
        dirs[:] = [d for d in dirs if d.startswith('sub-')]

        for sub_dir in dirs:
            # Construct the full path to the sub- directory
            sub_path = os.path.join(root, sub_dir)

            # Walk through the sub- directory recursively to find ses- folders
            for sub_root, sub_dirs, sub_files in os.walk(sub_path):
                # Filter sub_dirs to include only those that contain 'ses'
                sub_dirs[:] = [d for d in sub_dirs if 'ses' in d]

                for ses_dir in sub_dirs:
                    for kk in kk_values:
                        # Construct the path to the output_diff folder for each KK value
                        output_diff_folder = os.path.join(folder, 'derivatives', 'mrs', sub_dir, ses_dir, 'mrs', kk, 'output_diff') # was output_diff_folder = os.path.join(sub_root, ses_dir, 'derivatives', kk, 'output_diff')
                        option_file = os.path.join(output_diff_folder, 'options.txt')

                        if os.path.exists(option_file):
                            print(f"Found options.txt: {option_file}")

                            # Extract participant number, session, and location
                            participant_number = sub_dir.split('-')[-1]
                            session = 'pre' if 'ses-1' in ses_dir else 'post'
                            location = kk

                            # Extract the tissue fraction data from options.txt
                            tissue_data = extract_tissue_fractions(option_file)
                            print(f"Extracted tissue data: {tissue_data}")  # for debugging
                            if tissue_data:
                                # Create a DataFrame for the extracted data
                                df = pd.DataFrame([{
                                    'participant_number': participant_number,
                                    'session': session,
                                    'location': location,
                                    'CSF': tissue_data['CSF'],
                                    'GM': tissue_data['GM'],
                                    'WM': tissue_data['WM']
                                }])

                                # Add the processed DataFrame to the list
                                all_data.append(df)

    if all_data:
        # Combine all DataFrames into one
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Save combined DataFrame to a new CSV file
        combined_csv_path = os.path.join(folder, 'derivatives', 'mrs', 'combined_tissue_fraction.csv')
        combined_df.to_csv(combined_csv_path, index=False)
        print(f"Combined tissue fraction data saved to {combined_csv_path}")
    else:
        print("No options.txt files found with tissue fraction data.")
