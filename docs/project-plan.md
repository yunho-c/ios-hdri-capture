# iOS High-Resolution HDRI Capture Plan

This project is now targeting a serious high-resolution HDRI capture app, not just an
ARKit environment-probe exporter. ARKit remains useful for pose tracking, live preview,
and a low-resolution lighting reference, but the production HDRI source should be a
custom capture pipeline built from bracketed still images or RAW/ProRAW frames.

The architecture remains hybrid:

- **Swift / SwiftUI / ARKit / AVFoundation** own the app, camera, pose tracking, capture
  UX, and device-specific camera configuration.
- **Metal** handles preview/debug visualization and can later accelerate reprojection
  or blending if Swift/Rust CPU processing is too slow.
- **Rust via UniFFI** owns deterministic image processing, HDR merge math,
  spherical/cubemap accumulation, and OpenEXR export.
- **OpenEXR** remains the final renderer-friendly output format.

## Phase 1: Native App and Rust Encoder Scaffold

Status: complete.

Build a native iOS app scaffold that can compile Swift and Rust together before doing
camera work.

1. Use XcodeGen as the project source of truth.
2. Create a SwiftUI app target named `HDRICapture`.
3. Add a Rust `hdri_encoder` crate exposed to Swift through UniFFI.
4. Verify the app can call a trivial Rust API from Swift.
5. Make the build scripts robust when launched from Xcode, including Finder-launched
   Xcode where `cargo` may not be on `PATH`.

Acceptance criteria:

- `xcodegen generate` creates the Xcode project.
- Rust tests pass.
- The iOS simulator app builds from CLI.
- Xcode build phases can find Cargo without relying on shell startup files.

## Phase 2: ARKit Probe Baseline and Live Preview

Status: complete.

Keep ARKit environment probes as a diagnostic baseline, not the final high-resolution
HDRI source.

1. Start an `ARWorldTrackingConfiguration`.
2. Enable `environmentTexturing = .automatic`.
3. Enable HDR environment textures with `wantsHDREnvironmentTextures = true`.
4. Show a live AR preview through `ARSCNView`.
5. Observe `AREnvironmentProbeAnchor` updates through `ARSessionDelegate`.
6. Display the probe texture metadata: dimensions, texture type, pixel format, mip
   levels, storage mode, and usage.

Acceptance criteria:

- The app shows a live camera/AR preview on device.
- At least one probe texture appears during manual testing.
- The probe texture is treated as a low-resolution reference, commonly around
  `256x256` per cubemap face, not a production HDRI.

## Phase 3: AVFoundation High-Resolution Capture Foundation

This phase creates the real capture source for the production HDRI pipeline.

1. Add an `AVCaptureSession` pipeline alongside the existing AR session.
2. Use `AVCapturePhotoOutput` for high-resolution still capture.
3. Choose a capture device and format explicitly:
   - Prefer the wide camera for stable geometry and predictable field of view.
   - Prefer RAW or Apple ProRAW when available.
   - Fall back to high-quality processed stills when RAW is unavailable.
4. Query and surface device capabilities:
   - `availableRawPhotoPixelFormatTypes`
   - Apple ProRAW support and enablement
   - maximum bracket count
   - supported photo dimensions and codecs
   - supported ISO and exposure-duration ranges
5. Add a capture settings model that records:
   - lens/camera identity
   - focal length and intrinsics when available
   - exposure duration
   - ISO
   - white balance gains
   - timestamp
   - AR camera transform at capture time
6. Build a manual single-shot capture path first, saving the image data and metadata
   into an in-memory capture session object.

Acceptance criteria:

- A physical iPhone can capture a full-resolution still from the app.
- The app records the AR pose and camera/exposure metadata for that still.
- The app exposes whether RAW/ProRAW is available on the current device.

## Phase 4: Bracketed HDR Capture

This phase captures enough exposure range for lighting, including bright windows and
lamps.

1. Implement exposure bracketing using `AVCapturePhotoBracketSettings`.
2. Prefer manual exposure brackets with fixed white balance and fixed focus.
3. Generate bracket plans in stops, for example:
   - quick: `[-2, 0, +2]`
   - standard: `[-4, -2, 0, +2, +4]`
   - extended: `[-6, -4, -2, 0, +2, +4, +6]`
4. Clamp the generated exposure duration and ISO to device-supported ranges.
5. Capture RAW/ProRAW brackets when possible; otherwise capture processed brackets.
6. Store each bracket group as a single directional sample with multiple exposures.
7. Disable or avoid features that conflict with bracket consistency, such as flash,
   automatic exposure changes during the bracket, and automatic white balance drift.

Acceptance criteria:

- A single button captures a bracket set for the current viewing direction.
- The bracket set records exposure values and image payloads consistently.
- Overexposed and underexposed bracket members can be identified for HDR merge.

## Phase 5: Guided Spherical Capture UX

This phase turns still capture into a complete HDRI acquisition workflow.

1. Use ARKit orientation and pose to guide the user through a sphere of target
   directions.
2. Start with a fixed capture pattern:
   - one horizontal ring
   - one upward ring
   - one downward ring
   - zenith and nadir shots where feasible
3. Show on-screen target markers for uncaptured, current, and completed directions.
4. Gate capture on stability:
   - device motion below a threshold
   - AR tracking not severely limited
   - exposure/focus/white balance locked
5. Store every bracket group with its target direction and actual AR transform.
6. Allow recapture of a direction if motion blur, tracking quality, or exposure
   coverage is poor.

Acceptance criteria:

- A user can complete a guided full-sphere capture session.
- Every required direction has a bracket group and pose metadata.
- The app can resume or discard an incomplete capture session cleanly.

## Phase 6: HDR Merge and Radiometric Normalization

This phase converts bracket groups into linear HDR directional images.

1. Decode each bracket image into a linear working representation.
2. Use RAW/ProRAW data where available to reduce tone-mapping and ISP ambiguity.
3. Estimate per-pixel radiance from the bracket stack using exposure duration and ISO.
4. Reject saturated highlights and deep-shadow noise when better bracket samples exist.
5. Apply white balance consistently across the bracket group.
6. Produce one linear HDR image per captured direction.
7. Store intermediate debug outputs so failures can be inspected outside the app.

Acceptance criteria:

- A bracket group merges into a visibly higher dynamic range linear image.
- Bright light sources retain detail from short exposures.
- Shadow detail comes from long exposures without dominating clipped highlights.

## Phase 7: Spherical Reconstruction

This phase projects directional HDR images into a final environment map.

1. Calibrate or estimate camera intrinsics for the chosen capture device and format.
2. Convert each pixel into a ray in camera space, then transform it into world space
   using the AR pose captured with the bracket group.
3. Accumulate samples into a high-resolution spherical representation:
   - equirectangular output for renderer compatibility
   - optional cubemap intermediate for simpler sampling and filtering
4. Blend overlaps using confidence weights based on:
   - distance from image center
   - motion/tracking quality
   - saturation/noise rejection from HDR merge
   - angular overlap with neighboring captures
5. Fill small gaps conservatively. Do not hallucinate large unseen regions without
   clearly marking the output as incomplete.
6. Support configurable output resolutions, with 4K equirectangular as the first
   serious target and 8K as an aspirational target after performance testing.

Acceptance criteria:

- Captured bracket groups project into a coherent 2:1 equirectangular HDR image.
- Seams are acceptable for a prototype and visible enough to debug.
- Output resolution is independent of ARKit's environment-probe resolution.

## Phase 8: OpenEXR Export and Share Workflow

This phase turns the reconstructed environment into a usable renderer asset.

1. Extend the Rust encoder API to accept linear floating-point equirectangular pixels.
2. Write 16-bit half-float or 32-bit float OpenEXR files.
3. Include metadata:
   - capture date
   - app version
   - output resolution
   - source capture count
   - bracket plan
   - optional device model and lens identity
4. Export through `UIActivityViewController`.
5. Keep a debug export option for intermediate artifacts, such as per-direction merged
   HDR images and a JSON manifest.

Acceptance criteria:

- The app exports a valid `.exr` file.
- Blender or another renderer can load the HDRI as environment lighting.
- Debug artifacts are sufficient to diagnose bad seams, exposure issues, or missing
  capture directions.

## Phase 9: Validation and Quality Bar

This phase decides whether the app is producing useful HDRIs rather than just files.

1. Validate with controlled scenes:
   - room with a bright window
   - room with a small lamp
   - outdoor shade plus sunlit region
2. Compare exports against:
   - ARKit probe baseline
   - a simple non-HDR panorama
   - a renderer preview with reflective and diffuse spheres
3. Inspect objective failures:
   - clipped highlights
   - noisy shadows
   - color shifts between directions
   - ghosting from motion
   - projection seams
   - missing zenith/nadir coverage
4. Add a repeatable fixture capture procedure for regression testing.

Acceptance criteria:

- The HDRI produces plausible directional lighting in a renderer.
- Highlights are materially better than ARKit's low-resolution environment probe.
- Known failure modes are visible in debug exports and documented in the app.

## Near-Term Recommendation

Do not continue the old Phase 3/4 path as the main product route. Instead:

1. Keep the ARKit probe exporter as an optional debugging baseline.
2. Implement Phase 3 next: AVFoundation high-resolution still capture with pose and
   exposure metadata.
3. Then implement bracketed HDR capture before investing in EXR projection/export.

The most important technical risk is not EXR writing; it is reliable radiometric
capture and alignment. The plan should therefore prove high-resolution bracket capture
and pose-tagged directional sampling before spending significant effort on final
renderer polish.
