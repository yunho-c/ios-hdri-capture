# HDRICapture

Native iOS prototype scaffold for capturing HDRI lighting data with ARKit and encoding it through a Rust backend.

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Build the Rust encoder for the simulator:

```sh
PLATFORM_NAME=iphonesimulator CONFIGURATION=Debug scripts/build-rust-ios.sh
```

Generate UniFFI Swift bindings:

```sh
scripts/generate-uniffi-swift.sh
```

Build the iOS simulator app from CLI:

```sh
xcodebuild \
  -project HDRICapture.xcodeproj \
  -scheme HDRICapture \
  -sdk iphonesimulator \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run Rust tests:

```sh
CARGO_BUILD_RUSTC_WRAPPER= RUSTC_WRAPPER= cargo test --manifest-path rust/hdri_encoder/Cargo.toml
```

## Xcode Notes

The checked-in source of truth for the iOS project is `project.yml`; `HDRICapture.xcodeproj` is generated and ignored.

For physical iPhone deployment, open the generated project in Xcode and select a development team for the `HDRICapture` target. Simulator builds do not require signing setup.

## Phase 2 Validation

Phase 2 starts an `ARWorldTrackingConfiguration` with automatic environment texturing and shows the live AR preview plus the latest environment probe texture metadata.

For runtime validation, use an ARKit-capable iPhone:

1. Generate the project with `xcodegen generate`.
2. Open `HDRICapture.xcodeproj` in Xcode.
3. Select a development team for the `HDRICapture` target.
4. Run the app on the iPhone and grant camera permission.
5. Move the phone around the room until the Environment Probe section reports a probe count and texture metadata.

The simulator build is useful as a compile check, but it should not be treated as proof that real environment probe textures are available.
