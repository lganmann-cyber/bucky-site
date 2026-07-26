# MONO 400 — timeless 400-speed B&W press film · Calibration notes

**Reference material studied:** scans of classic 400-speed B&W press film
(street/photojournalism archives, darkroom community scans, lab sample rolls).

## Observed characteristics

- **Punchy, confident contrast.** Deep toe, steep mids, long printable
  shoulder — highlights hold texture forever, shadows commit early.
- **Big honest grain.** The defining texture: obvious, clumpy, uniform-ish
  across mids with cleaner extreme highlights. Pure luma — any color speckle
  destroys the read.
- **True blacks.** No lift, no toning at v1 (selenium/sepia = later feature).
- **Panchromatic rendering.** Skies darker than digital B&W conversions,
  skin slightly lighter.

## Parameter mapping (→ `FilmStockLibrary.mono400`)

- Desaturation *before* grain in the pipeline → grain stays luma naturally
- Contrast: symmetric punch curve [0, .19, .5, .81, 1], `gamma 1.05`
- Grain: `intensity 0.18, size 0.7, chromaMix 0.0, shadowWeight 0.55`
- Shoulder: `highlightRolloff 0.85`

## Iteration log

- v1: shadowWeight 0.8 left highlights suspiciously clean — real scans show
  grain in bright walls too → 0.55.
- v3 (device test): every stock's grain size was ~3x too coarse — 2‰-class
  clumps render ~9 px wide on 12 MP and read as circular blobs, amplified
  by Lanczos-upscaled noise in the CI fallback. All sizes recalibrated to
  0.35–0.95‰ and the fallback now scales noise nearest-neighbor with a
  0.25x clump blur.
