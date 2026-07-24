# OldSnap

Native iOS app that makes modern iPhone photos look like they were shot on
real film cameras. Two modes: a live camera (vintage viewfinder with the film
look applied in real time) and import/develop (transform camera-roll photos,
single or bulk up to 36). Photos live in an in-app library organized as film
rolls that develop on a lab timer.

**Stack:** Swift + SwiftUI (iOS 16+), Core Image pipeline with a stitchable
Metal grain kernel (pure-CI procedural fallback), StoreKit 2 via RevenueCat,
no backend, no accounts. All photos stay on device.

**Design language** (`DesignSystem/Theme.swift`): Locket-style — near-black
warm background with an amber glow rising from the bottom, SF Pro Rounded
bold type in sentence case, full-width amber pill CTAs with dark labels and a
trailing arrow, dark rounded cards/fields (continuous corners), gray pill
disabled states. The app runs dark-mode only (`UIUserInterfaceStyle = Dark`).

## Building

1. Open `OldSnap.xcodeproj` in **Xcode 16+**.
2. Let SPM resolve the RevenueCat package (`purchases-ios-spm`).
3. Set your signing team on the OldSnap target.
4. Run on a device (see hardware notes below — the simulator has no camera).

No further setup: the Info.plist is generated from build settings
(`GENERATE_INFOPLIST_FILE`), including camera/photo usage strings.

### Configuration points

| What | Where |
|---|---|
| RevenueCat API key (placeholder) | `App/AppConfig.swift` → `revenueCatAPIKey` |
| Bundle ID | `com.timberline.oldsnap` (project setting + `AppConfig`) |
| Pricing / paywall copy / product IDs | `Paywall/PaywallConfig.swift` |
| Social proof count (nil = hidden, never fabricate) | `AppConfig.socialProofCount` |
| Film Profile matrix (12 profiles) | `Onboarding/OnboardingModels.swift` |
| Preset parameters | `Engine/FilmStockLibrary.swift` + `Engine/Calibration/*.md` |
| App icon art direction | `docs/AppIcon-ArtDirection.md` |

While `revenueCatAPIKey` contains `PLACEHOLDER`, the app uses a mock purchase
service so the entire funnel (paywall → purchase → entitlement → lapsed) is
testable without StoreKit. Swap in the real key to go live.

### RevenueCat dashboard setup (when going live)

- Entitlement: `pro`
- Offerings: `default` (packages for `os_yearly_3499`, `os_weekly_499` with a
  3-day free trial) and `downsell` (`os_lifetime_6999` — or swap the package
  to `os_yearly_intro_2499` to A/B the downsell without an app update).

## The film engine

One parametric pipeline (`Engine/FilmEngine.swift`); every camera is a
`FilmStock` value (`Engine/FilmStockLibrary.swift`). No LUT-only looks, no
baked overlay textures:

- Color science is a parametric model (per-channel curves, split toning, film
  shoulder, black lift, WB cast) baked into a cached 33³ color cube per stock.
- Grain is procedural value-noise (Metal `[[stitchable]]` kernel in
  `Engine/Kernels.metal`, seeded, resolution-relative, shadow-weighted, with
  a pure Core Image fallback).
- Halation is threshold → blur → tint → screen, sized relative to the image.
- Light leaks, flash falloff, dust, date stamps are sampled per shot from a
  stored seed — re-renders are pixel-stable, re-rolls draw a new seed.

Calibration notes for each of the 10 cameras live in `Engine/Calibration/`,
with the deepest docs on the three viral looks (35C, DC-2000, 800T). The
dev-build **preset comparison grid** (Settings → Developer → Preset grid)
renders one photo through all presets for side-by-side iteration.

## Needs validation on real hardware

Flagging per the build spec — these can't be verified in this environment
(no Xcode/simulator here) and several can't be verified in a simulator at all:

1. **Full build compile.** Written for Xcode 16 / iOS 16 SDK; expect at most
   minor fixups on first build. The pbxproj uses Xcode 16's synchronized
   folders, so added/renamed files are picked up automatically.
2. **Metal grain kernel load** (`default.metallib` + `MTLLINKER_FLAGS =
   -framework CoreImage`). If it fails, the engine silently uses the CI
   fallback — verify grain visually in the preset grid either way.
3. **Live viewfinder framerate** on iPhone 12 (the floor device): preview
   renders at ≤1080p with a frame-drop policy (quality degrades before
   framerate). Profile with Instruments; lower `targetEdge` in
   `CameraController` if needed.
4. **36 × 12 MP bulk develop memory** — the queue is serial with
   autoreleasepools; confirm no memory warnings on device.
5. **Camera capture, flash, volume-button shutter** (AVCaptureEventInteraction,
   iOS 17.2+), haptics, silent-switch behavior of synthesized shutter sounds.
6. **StoreKit sandbox** once a real RevenueCat key is in.
7. **Local notification** delivery for roll-ready pings.

## Ship checklist (App Review)

- Paywall states price, period, renewal, and cancel path in plain text;
  restore purchases + terms + privacy links present (3.1.2).
- Photo/camera permission prompts are primed with purpose screens; app
  functions with "limited" photo access.
- Rating prompt fires exactly once (onboarding step 9) via the system API.
- Notification permission asked only after the first roll develops.
- No real film/camera trademarks anywhere in app or metadata.
- Replace the synthesized onboarding sample scene
  (`Onboarding/SampleImageFactory.swift`) with licensed photography, and the
  app icon placeholder per `docs/AppIcon-ArtDirection.md`.
