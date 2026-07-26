# CHROME 64 — '60s–'70s slide film · Calibration notes

**Reference material studied:** archival scans of the legendary discontinued
64-speed slide film: magazine-era editorial archives, Kodachrome-project
community scans, family slide-carousel digitizations.

## Observed characteristics

- **Reds own the frame.** The signature: reds saturated and slightly orange,
  glowing against everything else. A red jacket becomes the photo.
- **Inky, honest shadows.** Slides project — shadows go genuinely black with
  barely-blue depth. No lift, no fade.
- **High micro-contrast, fine grain.** Extremely sharp-reading scans; grain
  near-invisible, pure luma.
- **Hard-ish highlights.** Slide film clips sooner than neg — bright skies
  block up; that's period-correct.
- **Restrained everything else.** Greens olive-leaning, blues deep but not
  vivid; the palette reads editorial, not "vintage filter."

## Parameter mapping (→ `FilmStockLibrary.chrome64`)

- Red priority: `curveR` shoulder above G/B, `saturation 1.16` (vibrance low
  so already-vivid reds still lead)
- Inky shadows: `blackLift 0`, deep curve toes, faint blue shadow tint
- Slide clipping: `highlightRolloff 0.35` (lowest among the film stocks)
- Fine grain: `intensity 0.07, size 0.4, chromaMix 0.05`
- Scan crispness: `sharpen 0.35`

## Iteration log

- v1: saturation 1.3 went postcard-fake → 1.16 with gamma 1.06 gets density
  from contrast instead of chroma.
- v3 (device test): every stock's grain size was ~3x too coarse — 2‰-class
  clumps render ~9 px wide on 12 MP and read as circular blobs, amplified
  by Lanczos-upscaled noise in the CI fallback. All sizes recalibrated to
  0.35–0.95‰ and the fallback now scales noise nearest-neighbor with a
  0.25x clump blur.
