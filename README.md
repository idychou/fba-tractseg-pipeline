# fba-tractseg-pipeline
This repository contains an end-to-end pipeline to: (1) run MRtrix3 multi-tissue FBA (FD, FC, FDC), (2) harmonize fixel metrics across sites/scanners (ComBat), (3) generate TractSeg bundle segmentations/TOMs/tractograms, (4) compute tract-specific fixel connectivity + smoothing, (5) run tract-based fixel statistics (CFE) using `fixelcfestats`.
