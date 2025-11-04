#!/bin/bash

# ------------------------------------------------------------------------------
# Script name:  voxel_overlap_final.sh
#
# Description:  
# Author:	Hanna Willis, 18/06/25
# Modified by: Juju, 28/10/2025

# ------------------------ SET UP ------------------------
subject='sub-01 sub-02 sub-03 sub-04 sub-05 sub-06 sub-07 sub-08 sub-09 sub-10 sub-11 sub-12 sub-13 sub-14 sub-15 sub-16 sub-17 sub-18'
time='ses-1 ses-2'
voxels='V1 M1'

# SET UP CSV FOR RESULTS 
DATA_LOC='/home/fs0/pfr545/scratch/Amb_project/data'

cd $DATA_LOC || exit
echo 'Subj, Voxel, Ses1_Voxel_Size, Ses2_Voxel_Size, Ses2_Non_Overlap_Size, Ses2_Overlap_Size' > /home/fs0/pfr545/scratch/Amb_project/data/derivatives/mrs/voxel_overlap.csv

# ------------------------ CALCULATE ANAT2STRUCT WARP ------------------------
# This section will create the warp files for each timepoint and each subject between anat and standard space 

for subj in $subject
do
	for timepoint in $time
	do 

# SET DIRECTORIES  
echo "setting directories for..." "$subj" "$timepoint" "$voxel"
ANAT=$DATA_LOC/$subj/$timepoint/anat
STAND=/cvmfs/fsl.fmrib.ox.ac.uk/el9/fsl/6.0.7.13/data/standard
WARP=$DATA_LOC/$subj/$timepoint/anat/warps

# MAKE DIRECTORY 
echo "making warp directory for..." "$subj" "$timepoint" "$voxel"
mkdir $DATA_LOC/"$subj"/"$timepoint"/anat/warps

# Create warp from anat to standard
echo "creating warps for..." "$subj" "$timepoint" "$voxel"
flirt -in "$ANAT"/*acq-MP2RAGE_T1w.nii.gz -ref $STAND/MNI152_T1_1mm.nii.gz -omat "$WARP"/struct2mni.mat -interp nearestneighbour 
fnirt --ref=$STAND/MNI152_T1_1mm.nii.gz --in="$ANAT"/*acq-MP2RAGE_T1w.nii.gz --aff="$WARP"/struct2mni.mat --cout="$WARP"/warpxfm_struct2mni.nii.gz
invwarp -w "$WARP"/warpxfm_struct2mni.nii.gz -o "$WARP"/warpxfm_mni2struct.nii.gz -r "$ANAT"/*acq-MP2RAGE_T1w.nii.gz

done
done

# ------------------------ CALCULATE VOXEL OVERLAP ------------------------------------
# This section will move the voxels from fsl_mrs space, resample them into real T1 space and then register them to the baseline visit. 
# Since I have three visits, we will need to do this 3 times. You will also need to do this step for the baseline visit (despite registering to this) 
# for the overlap fsl_maths calculation to work. 

for subj in $subject
do
	for voxel in $voxels 
	do

# SET DIRECTORIES
ANAT_base=$DATA_LOC/$subj/ses-1/anat
WARP_base=$DATA_LOC/$subj/ses-1/anat/warps
ANAT_S2=$DATA_LOC/$subj/ses-2/anat # was ANAT_6m
WARP_S2=$DATA_LOC/$subj/ses-2/anat/warps # was WARP_6m
STAND=/cvmfs/fsl.fmrib.ox.ac.uk/el9/fsl/6.0.7.13/data/standard

FSL_MRS_DIR_BASE=/home/fs0/pfr545/scratch/Amb_project/data/derivatives/mrs/$subj/ses-1/mrs/ # remeber to add the voxel part later
FSL_MRS_DIR_S2=/home/fs0/pfr545/scratch/Amb_project/data/derivatives/mrs/$subj/ses-2/mrs/ # was FSL_MRS_DIR_6m
#FSL_MRS_DIR_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/mrs/$voxel/fsl_mrs
# ANAT_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/anat
# WARP_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/anat/warps

echo "STARTING" "$subj"
echo "RUNNING REGISTRATIONS FOR" "$subj"

# 1. CREATE REG FROM 6MONTH TO BASELINE 
# -------------------------------------------------
# Create struct2struct warp from 6month/9month to baseline 
flirt -in "$ANAT_S2"/*acq-MP2RAGE_T1w.nii.gz -ref "$ANAT_base"/*acq-MP2RAGE_T1w.nii.gz -out "$WARP_S2"/my_6m_struct2struct.nii.gz -omat "$WARP_S2"/my_6m_struct2struct.mat #-interp nearestneighbour
#flirt -in $ANAT_9m/anat.nii.gz -ref $ANAT_base/anat.nii.gz -out $WARP_9m/my_9m_struct2struct.nii.gz -omat $WARP_9m/my_9m_struct2struct.mat #-interp nearestneighbour

# Check two t1s are aligned - just make sure they are registered to each other 
fsleyes "$ANAT_base"/*acq-MP2RAGE_T1w.nii.gz "$WARP_S2"/my_6m_struct2struct.nii.gz

# 2. MOVE 6MONTH VOXEL INTO BASELINE SPACE 
# -------------------------------------------------

# add voxels HERE!!!

# Resample 6month fsl_mrs mask into t1 space 
flirt -applyxfm -usesqform -in "$FSL_MRS_DIR_S2"/mask.nii.gz -ref "$ANAT_S2"/anat.nii.gz -out "$FSL_MRS_DIR_S2"/6month_mask_full_fov.nii.gz

# Register 6month fsl_mrs mask into baseline t1 space 
flirt -applyxfm -in "$FSL_MRS_DIR_S2"/6month_mask_full_fov.nii.gz -ref "$ANAT_base"/anat.nii.gz -init "$WARP_S2"/my_6m_struct2struct.mat -out "$FSL_MRS_DIR_BASE"/6month_mask_reg.nii.gz

# 3. MOVE 9MONTH VOXEL INTO BASELINE SPACE 
# -------------------------------------------------
# Resample 9month fsl_mrs mask into t1 space 
# flirt -applyxfm -usesqform -in $FSL_MRS_DIR_9m/mask.nii.gz -ref $ANAT_9m/anat.nii.gz -out $FSL_MRS_DIR_9m/9month_mask_full_fov.nii.gz

# # Register 9month fsl_mrs mask into baseline t1 space 
# flirt -applyxfm -in $FSL_MRS_DIR_9m/9month_mask_full_fov.nii.gz -ref $ANAT_base/anat.nii.gz -init $WARP_9m/my_9m_struct2struct.mat -out $FSL_MRS_DIR_BASE/9month_mask_reg.nii.gz

# 4. RESAMPLE BASELINE VOXEL INTO BASELINE SPACE 
# -------------------------------------------------
# Edit FoV on baseline voxel so you can use fslmath (its slightly cut off compared to the t1)
flirt -in "$FSL_MRS_DIR_BASE"/mask.nii.gz -ref "$ANAT_base"/anat.nii.gz -applyxfm -usesqform -out "$FSL_MRS_DIR_BASE"/baseline_mask_fov.nii.gz

# 5. Calculate overlap 
# -------------------------------------------------
echo "CALCULATING OVERLAP FOR" $subj
fslmaths $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -sub $FSL_MRS_DIR_BASE/6month_mask_reg.nii.gz $FSL_MRS_DIR_BASE/6m_mrs_non_overlap.nii.gz
fslmaths $FSL_MRS_DIR_BASE/6m_mrs_non_overlap.nii.gz -thr 0 $FSL_MRS_DIR_BASE/6m_mrs_non_overlap_thr.nii.gz
fslmaths $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -mas $FSL_MRS_DIR_BASE/6month_mask_reg.nii.gz $FSL_MRS_DIR_BASE/6m_mrs_overlap.nii.gz

fslmaths $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -sub $FSL_MRS_DIR_BASE/9month_mask_reg.nii.gz $FSL_MRS_DIR_BASE/9m_mrs_non_overlap.nii.gz
fslmaths $FSL_MRS_DIR_BASE/9m_mrs_non_overlap.nii.gz -thr 0 $FSL_MRS_DIR_BASE/9m_mrs_non_overlap_thr.nii.gz
fslmaths $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -mas $FSL_MRS_DIR_BASE/9month_mask_reg.nii.gz $FSL_MRS_DIR_BASE/9m_mrs_overlap.nii.gz

# 6. Input values into a spreadsheet 
# -------------------------------------------------
baseline_size=`fslstats $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -V`
baseline_size2=`echo "$baseline_size" | awk '{print $2}'`

sixmonth_size=`fslstats $FSL_MRS_DIR_BASE/6month_mask_reg.nii.gz -V`
sixmonth_size2=`echo "$sixmonth_size" | awk '{print $2}'`

ninemonth_size=`fslstats $FSL_MRS_DIR_BASE/9month_mask_reg.nii.gz -V`
ninemonth_size2=`echo "$ninemonth_size" | awk '{print $2}'`

non_overlap_size_6m=`fslstats $FSL_MRS_DIR_BASE/6m_mrs_non_overlap.nii.gz -V`
non_overlap_size_6m2=`echo "$non_overlap_size_6m" | awk '{print $2}'`

overlap_size_6m=`fslstats $FSL_MRS_DIR_BASE/6m_mrs_overlap.nii.gz -V`
overlap_size_6m2=`echo "$overlap_size_6m" | awk '{print $2}'`

non_overlap_size_9m=`fslstats $FSL_MRS_DIR_BASE/9m_mrs_non_overlap.nii.gz -V`
non_overlap_size_9m2=`echo "$non_overlap_size_9m" | awk '{print $2}'`

overlap_size_9m=`fslstats $FSL_MRS_DIR_BASE/9m_mrs_overlap.nii.gz -V`
overlap_size_9m2=`echo "$overlap_size_9m" | awk '{print $2}'`

# 7. Save the data  
# -------------------------------------------------
echo "SAVING DATA FOR" $subj
echo $subj, $voxel, $baseline_size2, $sixmonth_size2, $non_overlap_size_6m2, $overlap_size_6m2, $non_overlap_size_9m2, $overlap_size_9m2  >> ~/scratch/Vision_Lab/Rehab/voxel_overlap.csv

done 
done 

# ------------------------ VISUALLY CHECK VOXELS ------------------------------------
# This section just allows you to open up the voxels and make sure they are all aligned - just a sanity check. 
for subj in $subject
do
	for voxel in $voxels 
	do

# SET DIRECTORIES 
ANAT_base=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/anat
WARP_base=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/anat/warps
ANAT_S2=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/anat
WARP_S2=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/anat/warps
STAND=/cvmfs/fsl.fmrib.ox.ac.uk/el9/fsl/6.0.7.13/data/standard
FSL_MRS_DIR_BASE=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/mrs/$voxel/fsl_mrs
FSL_MRS_DIR_6m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/mrs/$voxel/fsl_mrs

echo "STARTING" $subj
fsleyes $ANAT_base/anat.nii.gz \
$FSL_MRS_DIR_BASE/6month_mask_reg.nii.gz -cm red \
$FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -cm blue \
$FSL_MRS_DIR_BASE/mrs_overlap.nii.gz

done
done

# ------------------------ MOVE VOXEL INTO STANDARD SPACE ------------------------
# This section allows you to move the voxels into standard space and then add them together to show the average voxel location 
# This is useful for paper etc.

# Now run through all subjects
for subj in $subject
do
for voxel in $voxels 
do

# SET DIRECTORIES
ANAT_base=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/anat
WARP_base=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/anat/warps
ANAT_S2=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/anat
WARP_S2=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/anat/warps
STAND=/cvmfs/fsl.fmrib.ox.ac.uk/el9/fsl/6.0.7.13/data/standard
FSL_MRS_DIR_BASE=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/baseline/mrs/$voxel/fsl_mrs
FSL_MRS_DIR_6m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/6month/mrs/$voxel/fsl_mrs
FSL_MRS_DIR_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/mrs/$voxel/fsl_mrs
ANAT_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/anat
WARP_9m=/home/fs0/hwillis/scratch/Vision_Lab/Rehab/$subj/9month/anat/warps

# 1. Move voxel into standard space
# -------------------------------------------------

echo "applying warps for..." $subj $timepoint $voxel
applywarp -r $STAND/MNI152_T1_1mm.nii.gz -i $FSL_MRS_DIR_BASE/baseline_mask_fov.nii.gz -o $FSL_MRS_DIR_BASE/baseline_mask_standard.nii.gz -w $WARP_base/warpxfm_struct2mni.nii.gz
applywarp -r $STAND/MNI152_T1_1mm.nii.gz -i $FSL_MRS_DIR_6m/6month_mask_full_fov.nii.gz -o $FSL_MRS_DIR_6m/6month_mask_standard.nii.gz -w $WARP_S2/warpxfm_struct2mni.nii.gz
applywarp -r $STAND/MNI152_T1_1mm.nii.gz -i $FSL_MRS_DIR_9m/9month_mask_full_fov.nii.gz -o $FSL_MRS_DIR_9m/9month_mask_standard.nii.gz -w $WARP_9m/warpxfm_struct2mni.nii.gz

fslswapdim $FSL_MRS_DIR_BASE/baseline_mask_standard.nii.gz -x y z $FSL_MRS_DIR_BASE/baseline_mask_standard_flip.nii.gz
fslswapdim $FSL_MRS_DIR_6m/6month_mask_standard.nii.gz -x y z $FSL_MRS_DIR_6m/6month_mask_standard_flip.nii.gz
fslswapdim $FSL_MRS_DIR_9m/9month_mask_standard.nii.gz -x y z $FSL_MRS_DIR_9m/9month_mask_standard_flip.nii.gz

done
done 

# Visually check all the voxels and check they are in standard space 
fsleyes  $FSL_MRS_DIR_BASE/baseline_mask_standard.nii.gz $FSL_MRS_DIR_6m/6month_mask_standard.nii.gz $FSL_MRS_DIR_9m/9month_mask_standard.nii.gz

# 2. Add all the standardised voxel together to make an average 
# -------------------------------------------------

# Flip all right hemis to left
STUDY_LOC=/home/fs0/hwillis/scratch/Vision_Lab/Rehab

# Baseline
# Add all baseline hMT+ voxels together  R002 R003 R010 R013 R014 R015 R017 R018 R022 R023
fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R017/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R018/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R020/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R023/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R024/baseline/mrs/hMT/fsl_mrs/baseline_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/hMT_voxel_sum_baseline_v2.nii.gz

fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R017/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R018/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R020/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R023/baseline/mrs/m1/fsl_mrs/baseline_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R024/baseline/mrs/m1/fsl_mrs/baseline_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/m1_voxel_sum_baseline_v2.nii.gz

# Six months
# Add all baseline m1 voxels together R002 R003 R010 R013 R014 R015 R017 R018 R022 R023
fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R013/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R017/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R018/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R020/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R023/6month/mrs/hMT/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R024/6month/mrs/hMT/fsl_mrs/6month_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/hMT_voxel_sum_6month_v2.nii.gz

fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R013/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R017/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R018/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R020/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R023/6month/mrs/m1/fsl_mrs/6month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R024/6month/mrs/m1/fsl_mrs/6month_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/m1_voxel_sum_6month_v2.nii.gz

# 9 months 
# Add all 6month hMT+ voxels together R002 R003 R010 R013 R014 R015 R017 R018 R022 R023
fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/9month/mrs/hMT/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/9month/mrs/hMT/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/9month/mrs/hMT/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/9month/mrs/hMT/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/9month/mrs/hMT/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/9month/mrs/hMT/fsl_mrs/9month_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/hMT_voxel_sum_9month_v2.nii.gz

# Add all 6month hMT+ voxels together R002 R003 R010 R013 R014 R015 R017 R018 R022 R023
fslmaths /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R002/9month/mrs/m1/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R003/9month/mrs/m1/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R004/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R005/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R006/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R007/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R010/9month/mrs/m1/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R011/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R014/9month/mrs/m1/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R015/9month/mrs/m1/fsl_mrs/9month_mask_standard_flip.nii.gz \
-add /home/fs0/hwillis/scratch/Vision_Lab/Rehab/R019/9month/mrs/m1/fsl_mrs/9month_mask_standard.nii.gz \
/home/fs0/hwillis/scratch/Vision_Lab/Rehab/scripts/mri_analysis/mrs/new_fsl_mrs/average_voxels/m1_voxel_sum_9month_v2.nii.gz

