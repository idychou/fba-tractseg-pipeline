#!/usr/bin/env bash
# compute_metrics.sh
#
# Compute FC, log(FC), and FDC metrics for fixel-based analysis (FBA).
#
# Reference:
#   https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html#
#
# Prerequisites:
#   - Subject-to-template warps already computed (mrregister -nl_warp)
#   - Template fixel mask already computed (fod2fixel on FOD template)
#   - Subject FD already mapped to template fixels (fixelcorrespondence -> template/fd/<sub>_PRE.mif)
#   - MRtrix3 on PATH (warp2metric, mrcalc)
#
# Created by Idy Chou on 12 Nov 2024

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
outDir="${topDir}"
templateDir="${topDir}/template"

subject_prefix="sub-"  
rf_algorithm="dhollander"
fod_algorithm="ss3t"
# ---------------------------------------------------------------------------

sep="-----------------------------------------------------------------------------"

# Template paths
fixelDir="${templateDir}/fixel_mask"

fdDir="${templateDir}/fd"
fcDir="${templateDir}/fc"
logDir="${templateDir}/log_fc"
fdcDir="${templateDir}/fdc"

# Prepare folders
mkdir -p "${fcDir}" "${logDir}" "${fdcDir}"

# Ensure fixel directory metadata exist (index & directions must match template fixels)
if [ ! -f "${fcDir}/index.mif" ]; then cp "${fdDir}/index.mif" "${fcDir}/index.mif"; fi
if [ ! -f "${fcDir}/directions.mif" ]; then cp "${fdDir}/directions.mif" "${fcDir}/directions.mif"; fi

if [ ! -f "${logDir}/index.mif" ]; then cp "${fdDir}/index.mif" "${logDir}/index.mif"; fi
if [ ! -f "${logDir}/directions.mif" ]; then cp "${fdDir}/directions.mif" "${logDir}/directions.mif"; fi

if [ ! -f "${fdcDir}/index.mif" ]; then cp "${fdDir}/index.mif" "${fdcDir}/index.mif"; fi
if [ ! -f "${fdcDir}/directions.mif" ]; then cp "${fdDir}/directions.mif" "${fdcDir}/directions.mif"; fi

cd "${topDir}"

for sub in ${subject_prefix}*; do
  [ -d "${sub}" ] || continue

  printf "%s\n%s\n%s\n" "${sep}" "${sub}" "${sep}"

  sub2templ_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_subject2template_warp.mif"

  # FC: computed from warps, stored in template/fc as <sub>_IN.mif by warp2metric
  if [ ! -f "${fcDir}/${sub}_IN.mif" ]; then
    printf "\nComputing fibre cross-section (FC) metric...\n"
    warp2metric "${sub2templ_file}" -fc "${fixelDir}" "${fcDir}" "${sub}_IN.mif"
  fi

  # log(FC): recommended for stats (centred around 0)
  if [ ! -f "${logDir}/${sub}_IN.mif" ]; then
    printf "\nComputing log(FC)...\n"
    mrcalc "${fcDir}/${sub}_IN.mif" -log "${logDir}/${sub}_IN.mif"
  fi

  # FDC = FD * FC (must be on same template fixels)
  if [ ! -f "${fdcDir}/${sub}_PRE.mif" ]; then
    printf "\nComputing fibre density and cross-section (FDC)...\n"
    mrcalc "${fdDir}/${sub}_PRE.mif" "${fcDir}/${sub}_IN.mif" -mult "${fdcDir}/${sub}_PRE.mif"
  fi

  printf "%s\nDone.\n" "${sep}"
done

printf "%s\nDone.\n" "${sep}"
cd ~
