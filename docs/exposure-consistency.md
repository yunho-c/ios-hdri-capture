# Exposure and White-Balance Consistency

This note captures the current understanding of how to reduce brightness, tone, and
white-balance jumps between spherical capture targets.

## Summary

Seam jumps are likely because the current ARKit high-resolution capture path lets the
camera continue auto exposure, auto white balance, and tone mapping while the user turns
around the room. We should improve this, but full manual exposure and white-balance lock
is not guaranteed through the current ARKit-owned camera path.

The recommended strategy is staged:

1. Add ARKit capture consistency checks first.
2. Add overlap-based post-capture normalization second.
3. Treat direct AVFoundation exposure/WB locking as a device-tested spike.

## Current API Reality

ARKit gives useful metadata but limited direct camera control:

- `ARCamera.exposureDuration` is available, but read-only.
- `ARCamera.exposureOffset` is available, but read-only.
- The current ARKit path does not expose white-balance metadata through `ARCamera`.
- iOS 26 adds `ARSession.captureHighResolutionFrameUsingPhotoSettings(_:completion:)`,
  which allows an ARKit high-resolution frame request to carry custom
  `AVCapturePhotoSettings`.

AVFoundation exposes stronger controls:

- `AVCaptureDevice.setExposureModeCustom(duration:iso:completionHandler:)` can lock
  exposure duration and ISO.
- `AVCaptureDevice.setWhiteBalanceModeLocked(...)` can lock white balance.
- `AVCaptureDevice.globalToneMappingEnabled` can request global rather than local tone
  mapping when supported.

The catch is camera ownership. ARKit owns the live camera session in the current app, so
directly configuring the underlying `AVCaptureDevice` while ARKit is running may be
ignored, overridden, or reset by ARKit. This needs real device validation before it
becomes a core quality assumption.

## Recommended Path

### 1. ARKit capture consistency mode

Add a capture mode that keeps the existing ARKit flow but rejects or warns about unstable
captures:

- Record the first target's exposure duration and exposure offset as the session
  reference.
- Before each target capture, wait briefly for tracking and exposure metadata to settle.
- Compare each captured frame against the reference exposure metadata.
- Warn or block when exposure offset drift exceeds a threshold such as `0.3 EV`.
- Add the drift values to per-target metadata and the manifest.
- On iOS 26 and newer, try `captureHighResolutionFrameUsingPhotoSettings` with
  photo settings configured for consistency/speed where possible.

This should be implemented before bracketed capture because bracket sets multiply any
per-target inconsistency problem.

### 2. Overlap-based normalization

Use the existing reprojection and target-index diagnostics to estimate exposure/color
matching between overlapping captures:

- For each pair of overlapping target images, sample common equirectangular pixels.
- Estimate per-target RGB gain or a simple color correction relative to a reference
  target.
- Apply the correction during preview/HDRI assembly, not to the original captured
  artifacts.
- Export the solved gains in the manifest for inspection.

This is likely more reliable than depending only on the camera remaining locked while
the user rotates through bright windows, dark walls, ceilings, and floors.

### 3. Manual lock spike

Prototype a device-only experiment that tries to lock the physical camera while ARKit is
active:

- Locate the back camera `AVCaptureDevice` matching the ARKit high-resolution format.
- Lock it for configuration.
- Try custom exposure duration/ISO and locked white-balance gains.
- Capture several spherical targets and inspect whether ARKit preserves those settings.
- Check whether ARKit resets settings after `session.run`, format changes, interruption,
  or high-resolution capture.

This should not be treated as guaranteed until tested on the target iPhone model and OS.

## Validation Checklist

For each approach, capture a scene with both a bright window and a darker interior wall:

- Inspect per-target exposure duration and exposure offset in `manifest.json`.
- Compare seams in `preview.jpg`.
- Use `target-index.png` to identify which source targets are causing visible seams.
- Check whether recapturing a target with worse exposure drift improves the seam.
- Repeat with `Fast 8`, `Balanced 14`, and `Full 18` patterns.

## References

- ARKit `ARCamera`: https://developer.apple.com/documentation/arkit/arcamera
- ARKit high-resolution frame capture:
  https://developer.apple.com/documentation/arkit/arsession/capturehighresolutionframe%28completion%3A%29
- AVFoundation `AVCaptureDevice`:
  https://developer.apple.com/documentation/avfoundation/avcapturedevice

