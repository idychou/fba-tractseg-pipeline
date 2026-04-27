#!/usr/bin/env bash
# run_tractseg.sh
#
# Run TractSeg on the (study-specific) FOD template:
#   1) Compute MRtrix peaks from the template WM FOD
#   2) Run TractSeg bundle segmentation (72 bundles) and endings segmentations
#   3) Create Tract Orientation Maps (TOMs)
#   4) Run bundle-specific tracking (Tracking on TOMs)
#
# Reference:
#   https://github.com/MIC-DKFZ/TractSeg
#
# Prerequisites:
#   - MRtrix3 on PATH (sh2peaks)
#   - TractSeg installed and on PATH (TractSeg, Tracking)
#   - FOD template exists: template/wm_fod_template.mif
#
# Created by Idy Chou on 21 Mar 2025

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
templateDir="${topDir}/template"
tractSegDir="${topDir}/group_data/tractSeg"

# Output tracking settings
tracking_format="tck"
nr_fibers="10000"

# Optional: set to 1 if you repeatedly see OpenMP / KMP duplicate library errors
export_KMP_DUPLICATE_LIB_OK=1
# ---------------------------------------------------------------------------

sep="--------------------------------------------------------"

# Create output directories
mkdir -p "${tractSegDir}"
mkdir -p "${tractSegDir}/tractseg_output"

# ------------------------ compute peaks from template -----------------------
printf "%s\nComputing peaks from template FOD...\n%s\n" "${sep}" "${sep}"

fod_file="${templateDir}/wm_fod_template.mif"
peaks_file="${tractSegDir}/wm_fod_template_peaks.nii.gz"

if [ ! -f "${fod_file}" ]; then
  echo "ERROR: Missing template FOD: ${fod_file}"
  exit 1
fi

if [ ! -f "${peaks_file}" ]; then
  sh2peaks "${fod_file}" "${peaks_file}"
fi

# ----------------------------- run TractSeg --------------------------------
cd "${tractSegDir}"

printf "%s\nSegmenting tracts using template peaks...\n%s\n" "${sep}" "${sep}"

if [ "${export_KMP_DUPLICATE_LIB_OK}" -eq 1 ]; then
  export KMP_DUPLICATE_LIB_OK=TRUE
fi

# Bundle segmentations
TractSeg -i "${peaks_file}" -o "${tractSegDir}/tractseg_output" --output_type tract_segmentation

# Start/end regions
TractSeg -i "${peaks_file}" -o "${tractSegDir}/tractseg_output" --output_type endings_segmentation

# Tract Orientation Maps (TOMs)
printf "%s\nCreating tract orientation maps (TOMs)...\n%s\n" "${sep}" "${sep}"
TractSeg -i "${peaks_file}" -o "${tractSegDir}/tractseg_output" --output_type TOM

# Bundle-specific tractograms (Tracking on TOMs)
printf "%s\nCreating bundle-specific tractograms...\n%s\n" "${sep}" "${sep}"
Tracking -i "${peaks_file}" \
  -o "${tractSegDir}/tractseg_output" \
  --tracking_format "${tracking_format}" \
  --nr_fibers "${nr_fibers}"

printf "%s\nDone.\n" "${sep}"
cd ~
