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

### 1) Preprocessing (choose ONE branch)

This repository supports **two DWI preprocessing pathways**, depending on whether you have
**reversed phase-encoding (blip-up/blip-down)** data or only a **single phase-encoding** DWI.

#### Option A — Reversed phase-encoding available (AP+PA, etc.)
1. `preprocess/preprocess_reversed_pe.sh`

#### Option B — Single phase-encoding only (uses Synb0-DISCO)
1. `preprocess/preprocess_single_pe_presynb0.sh <sub-id>`
2. Run **Synb0-DISCO** externally (not included in this repository)
3. `preprocess/preprocess_single_pe_postsynb0.sh <sub-id>`

> Notes (single-PE / Synb0 workflow):
> - The pre-synb0 script denoises + removes Gibbs ringing, extracts mean `b=0`,
>   computes Total Readout Time (TRT), and stages inputs for Synb0-DISCO.
> - The post-synb0 script runs `dwifslpreproc` using the **Synb0-synthesized undistorted `b=0`**
>   as the `-se_epi` reference.
> - If you enable eddy slice-to-volume correction (`--mporder`), you must provide a valid
>   `slspec` file (slice acquisition order). See the post-synb0 script header / variables.

---

### 2) FBA + Harmonization + TractSeg (run order)

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
- FSL (including `topup`/`eddy` if using `dwifslpreproc`; `bet` is used in the bias/mask step)
- TractSeg
- MATLAB (or GNU Octave if compatible with the `.m` scripts)
- R (for ComBat harmonization)

### Additional requirements (single-PE pathway only)
- Synb0-DISCO (external; run separately)
- ANTs (required if using `dwibiascorrect ants` in the post-synb0 script)

---

## How to run

### 1) Preprocessing

#### Option A — Reversed phase-encoding (AP/PA)
bash preprocess/preprocess_reversed_pe.sh

#### Option B — Single phase-encoding + Synb0-DISCO
##### Pre-Synb0: denoise/degibbs + stage Synb0 inputs
bash preprocess/preprocess_single_pe_presynb0.sh sub-XXX

##### Run Synb0-DISCO externally (see Synb0-DISCO documentation)

##### Post-Synb0: dwifslpreproc using synthesized undistorted b0 + optional bias correction
bash preprocess/preprocess_single_pe_postsynb0.sh sub-XXX

### 2) FBA + Harmonization + TractSeg
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
