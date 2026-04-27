# Tract-based Fixel-Based Analysis (FBA) + Harmonization + TractSeg

This repository contains an end-to-end pipeline to:
- run MRtrix3 multi-tissue FBA (FD, FC, log(FC), FDC),
- harmonize fixel metrics across sites/scanners (ComBat),
- generate TractSeg bundle segmentations/TOMs/tractograms,
- compute tract-specific fixel connectivity + smoothing,
- run tract-based fixel statistics (CFE) using `fixelcfestats`.

---

## References (methods / software)

### TractSeg
- Paper: `https://doi.org/10.1016/j.neuroimage.2018.07.070`
- Code: `https://github.com/MIC-DKFZ/TractSeg.git`

### Fixel-based analysis (FBA)
- MRtrix3: `https://www.mrtrix.org/`
- MRtrix3Tissue (SS3T-CSD): `https://3tissue.github.io/doc/ss3t-csd.html`

### ComBat harmonization
- Paper: `https://doi.org/10.2967/jnumed.121.262464`
- Code: `https://github.com/Jfortin1/ComBatHarmonization.git`

---

## Pipeline overview (run order)

1. `fba/estimate_rf.sh`
2. `fba/calculate_average_rf.sh`
3. `fba/estimate_fod.sh`
4. `fba/register_fod.sh`
5. `fba/prep_fba_inputs.sh`
6. `fba/compute_metrics.sh`
7. `harmonize/mif_to_matrix.m`
8. `harmonize/combat_harmonize.R`
9. `harmonize/harmonized_to_mif.m`
10. `fba/run_tractseg.sh`
11. `fba/tract_to_fixel.sh`
12. `fba/run_fixel_stats.sh`

---

## Requirements

- MRtrix3
- FSL
- TractSeg
- MATLAB (or GNU Octave if compatible with the `.m` scripts)
- R (for ComBat harmonization)

---

## How to run

```bash
bash fba/estimate_rf.sh
bash fba/calculate_average_rf.sh
bash fba/estimate_fod.sh
bash fba/register_fod.sh
bash fba/prep_fba_inputs.sh
bash fba/compute_metrics.sh

matlab -nodisplay -r "run('harmonize/mif_to_matrix.m'); exit"
Rscript harmonize/combat_harmonize.R
matlab -nodisplay -r "run('harmonize/harmonized_to_mif.m'); exit"

bash fba/run_tractseg.sh
bash fba/tract_to_fixel.sh
bash fba/run_fixel_stats.sh
