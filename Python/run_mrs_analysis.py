#!/usr/bin/env python

## import dependencies 
import os
import sys
import fsl_mrs
import ast
import matplotlib
from matplotlib import pyplot as plt
import glob
import shutil
import re
import warnings 
import subprocess
import json
import pandas as pd 
import fsl_mrs.utils.mrs_io as mrs_io
from fsl_mrs_preproc_edit import main as preproc_edit
import fsl_mrs_preproc_edit 
import MRS_process_pipeline
import joblib
import fsl
import argparse

# exclude_list = ['sub-05', 'sub-02', 'sub-08', 'sub-06', 'sub-01', 'sub-09', 'sub-03', 'sub-10', 'sub-04', 'sub-07']
# data = "/home/fs0/pfr545/scratch/Amb_project/data/" 

def run_mrs_analysis(data, exclude_list = None, phase_corr=True): #

    if exclude_list is not None:
        exclude_list = ast.literal_eval(exclude_list)
    else:
        exclude_list = None

    if phase_corr:
        preproc_wr = 'phase_corr'
    else:
        preproc_wr = None

    MRS_process_pipeline.process_files_with_spec2nii(data, exclude=exclude_list) #2min each
    MRS_process_pipeline.preproc(data, preproc_wr, exclude=exclude_list) # takes 4min each
    MRS_process_pipeline.MRS_anat_process(data, exclude=exclude_list) # takes 24 min each 
    MRS_process_pipeline.svs_segment_process(data, exclude=exclude_list)
    MRS_process_pipeline.mrs_analysis_process(data, exclude=exclude_list)

    MRS_process_pipeline.process_summary_files(data)
    MRS_process_pipeline.process_QC_files(data)
    MRS_process_pipeline.process_tissue_fraction_files(data)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run MRS analysis.")
    parser.add_argument("--data", required=True, help="Path to data")
    parser.add_argument("--exclude_list", type=str, default=None, help="add all the participant you do not wish to process in the form <sub-09>")
    parser.add_argument("--phase_corr", action="store_true", help="Enable phase correction")

    args = parser.parse_args()

    run_mrs_analysis(args.data, args.exclude_list, args.phase_corr)