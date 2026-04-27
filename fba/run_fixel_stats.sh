#!/usr/bin/env bash
# run_fixel_stats.sh
#
# Perform tract-based statistical analysis on fixel-wise metrics using fixelcfestats.
# This script assumes you already:
#   - generated tract-specific fixel directories for each metric (e.g., fd_smooth/<tract>/)
#   - generated tract-specific fixel-fixel connectivity matrices (matrix/<tract>/)
#   - prepared design matrix / contrasts / f-tests and files lists
#
# Reference:
#   https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html#
#
# Created by Idy Chou on 26 Mar 2025

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"

tractDir="${topDir}/TractSeg"
designDir="${tractDir}/design"

metric="fd"                             # fd | log_fc | fdc
metricDir="${tractDir}/${metric}_smooth" # contains one directory per tract
statDir="${tractDir}/stats_${metric}"
matDir="${tractDir}/matrix"              # contains one directory per tract

# Use patient design files?
pat=0                                    # 0 = no, 1 = yes

# Include variance file?
use_variance=0                           # 0 = no, 1 = yes

# fixelcfestats settings
nshuffles="3000"
# ---------------------------------------------------------------------------

sep="-----------------------------------------------------------------------------"

mkdir -p "${statDir}"

# Select design inputs
if [ "${pat}" -eq 0 ]; then
  files="${designDir}/files.txt"
  design="${designDir}/design.txt"
  contrast="${designDir}/contrast.txt"
  ftests="${designDir}/ftests.txt"
  variance_file="${designDir}/variance.txt"
else
  files="${designDir}/files_pat.txt"
  design="${designDir}/design_pat.txt"
  contrast="${designDir}/contrast_pat.txt"
  ftests="${designDir}/ftests_pat.txt"
  variance_file="${designDir}/variance_pat.txt"
fi

# Copy design files to output directory (for provenance)
cp -f "${design}" "${contrast}" "${ftests}" "${statDir}/"
if [ "${use_variance}" -eq 1 ]; then
  cp -f "${variance_file}" "${statDir}/"
fi

# Main function
cd "${metricDir}" || exit 1

x=0
for tract in *; do
  [ -d "${tract}" ] || continue

  x=$((x + 1))
  echo "${x} ${tract}"

  tract_metric_dir="${metricDir}/${tract}"
  tract_matrix_dir="${matDir}/${tract}"
  tract_stat_dir="${statDir}/${tract}"

  # Check inputs
  if [ ! -d "${tract_matrix_dir}" ]; then
    echo "WARNING: Missing matrix directory for tract ${tract}: ${tract_matrix_dir} (skipping)"
    continue
  fi

  # Create output directory
  mkdir -p "${tract_stat_dir}"

  # Copy file list into the tract metric directory (optional convenience)
  cp -f "${files}" "${tract_metric_dir}/"

  # Run fixelcfestats
  if [ "${use_variance}" -eq 0 ]; then
    fixelcfestats \
      "${tract_metric_dir}" \
      "${files}" \
      "${design}" \
      "${contrast}" \
      "${tract_matrix_dir}" \
      "${tract_stat_dir}" \
      -ftests "${ftests}" \
      -nshuffles "${nshuffles}"
  else
    fixelcfestats \
      "${tract_metric_dir}" \
      "${files}" \
      "${design}" \
      "${contrast}" \
      "${tract_matrix_dir}" \
      "${tract_stat_dir}" \
      -ftests "${ftests}" \
      -nshuffles "${nshuffles}" \
      -variance "${variance_file}"
  fi
done

printf "%s\nDone.\n" "${sep}"
cd ~
