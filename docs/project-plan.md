Here is a strategic, phase-by-phase implementation plan for building your iOS HDRI capture prototype.

Given the heavy lifting required for memory management and file encoding, this plan advocates for a hybrid architecture: using native Swift for the AR/GPU pipeline and a systems language for the encoding logic, avoiding the overhead of a cross-platform UI framework until the core technology is proven.

### Phase 1: Architecture & Tech Stack

For a high-performance graphics utility, you want to minimize the layers between the camera, the GPU, and the file system.

*   **Frontend & AR Pipeline: Native Swift.** Interacting directly with ARKit and Metal is significantly cleaner in Swift. Wrapping MTLTexture memory buffers in cross-platform frameworks (like Flutter) early in prototyping often introduces unnecessary FFI latency and debugging headaches.
    
*   **Encoding Backend: Rust.** Swift does not have robust, native libraries for writing OpenEXR or Radiance HDR files. You can write a Rust core utilizing the exr or image crates, compile it as a static library for iOS (aarch64-apple-ios), and generate Swift bindings (using tools like UniFFI or swift-bridge).
    
*   **Target Output:** A 32-bit float OpenEXR (.exr) equirectangular image, which is the standard format expected by rendering engines like Marmoset Toolbag, Blender, or custom ray tracers.
    

### Phase 2: The ARKit Capture Pipeline

Your first technical milestone is getting ARKit to generate the data.

1.  **Session Configuration:** Initialize an ARWorldTrackingConfiguration.
    
2.  **Enable Machine Learning In-filling:** Set the environmentTexturing property to .automatic. This tells ARKit to continuously analyze the camera feed and project it onto a 360-degree sphere, using CoreML to hallucinate the lighting for areas behind the phone.
    
3.  **Extract the Anchor:** Implement the ARSessionDelegate. When ARKit feels it has enough data, it will output an AREnvironmentProbeAnchor.
    
4.  **Isolate the Texture:** Access the anchor's environmentTexture property. This will return an MTLTexture configured as a typeCube (a cubemap with 6 distinct faces).
    

### Phase 3: The Metal-to-CPU Bridge (The Critical Path)

This is the most complex phase. The MTLTexture exists in GPU memory. You cannot simply save it to disk; you must marshal that data back to the CPU.

1.  **Allocate CPU Memory:** Check the pixelFormat of the MTLTexture. ARKit typically outputs rgba16Float (half-precision). Calculate the byte size: width \* height \* 4 channels \* 2 bytes \* 6 faces. Allocate a contiguous Swift Data buffer or a standard \[Float16\] array of this exact size.
    
2.  **Extract the Bytes:** Loop through the 6 faces (slices) of the MTLTexture cubemap. Use the Metal method getBytes(\_:bytesPerRow:bytesPerImage:from:mipmapLevel:slice:) to copy the pixel data from the GPU into your pre-allocated CPU array.
    
3.  **Format Conversion (Optional but likely):** If your Rust EXR encoder expects 32-bit floats (f32), you will need to iterate through the Float16 array on the CPU and cast them to Float32 before passing them across the FFI boundary.
    

### Phase 4: Equirectangular Projection & Encoding

Standard HDRIs used in 3D rendering are usually 2D lat-long equirectangular images, not raw 6-face cubemaps. You need to transform the data before encoding.

1.  **The FFI Handshake:** Pass a pointer to your flattened Float32 array and the texture dimensions to your Rust backend.
    
2.  **Cubemap to Equirectangular Math:** In Rust, write a compute function to unwrap the 6 cubemap faces into a single 2:1 equirectangular image grid. This involves iterating over the destination image pixels, converting their 2D coordinates into 3D spherical directional vectors, and sampling the corresponding color from the cubemap array.
    
3.  **File Writing:** Use your Rust EXR crate to compress and write the resulting byte array to a temporary file path on the iOS device.
    
4.  **Export:** Back in Swift, use UIActivityViewController to present the iOS Share Sheet, allowing the user to Airdrop the .exr file to their Mac or save it to the Files app.
    

### Phase 5: Testing & Validation

1.  **Simulator Validation:** Run the Swift code in the Xcode Simulator. Walk around the virtual living room and trigger the capture pipeline.
    
2.  **Hex Inspection:** Ensure the file exports correctly and is a valid EXR by throwing it into a desktop renderer. It should look exactly like the Xcode simulator room.
    
3.  **Real-World ML Test:** Deploy to a physical iPhone. Stand in a room with a distinct light source (like a single bright window). Move the phone around, export the EXR, and apply it to a sphere in a 3D engine to evaluate if the directional light intensities and shadows were captured accurately by Apple's ML model.
