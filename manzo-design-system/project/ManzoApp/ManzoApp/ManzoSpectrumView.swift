import AppKit
import Metal
import MetalKit

// ManzoSpectrumView: MTKView subclass for the real-time spectrum analyzer.
//
// Dimensions: 225 × 32 pt (75 bars × 3 pt/bar; 32 pt = 16 height levels × 2 pt/level).
// Pixel format: .rgba16Float via CAMetalLayer (NOT MTKView.colorPixelFormat — SPEC-01).
// Colorspace: displayP3 set explicitly — MTKView does NOT auto-configure P3 (spike 010 landmine).
// Render loop: CADisplayLink on a dedicated background thread (SPEC-04).
//
// Architecture note: ManzoSpectrumView holds an optional reference to the Rust handle pointer
// passed from AppDelegate. The handle's lifetime is owned by AppDelegate.
class ManzoSpectrumView: MTKView {

    // MARK: - Metal objects

    private var commandQueue: MTLCommandQueue?
    private var barPipelineState: MTLRenderPipelineState?
    private var peakPipelineState: MTLRenderPipelineState?

    // MARK: - Buffers

    // fftBuffer: shared storage for 75 float32 bar heights (range [0.0, 1.0]).
    // Filled each frame by calling manzo_get_spectrum via FFI.
    // storageModeShared: CPU-writable and GPU-readable without explicit copy (SPEC-02).
    // On Apple Silicon unified memory, writing via manzo_get_spectrum is an ARM STORE
    // directly to the same physical RAM the GPU reads — no cross-bus copy (SPEC-02).
    private var fftBuffer: MTLBuffer!

    // barVertexBuffer: 75 bars × 6 vertices (2 triangles per quad).
    // Each vertex: float2 NDC position + float barIndex + float barHeight = 4 floats = 16 bytes.
    // Quads extended by 3σ=6 pt on all sides for SDF bloom (D-03 / spike 011).
    private var barVertexBuffer: MTLBuffer!

    // peakVertexBuffer: 75 peak dots × 6 vertices × 4 floats.
    private var peakVertexBuffer: MTLBuffer!

    // MARK: - Peak-hold state (D-14, D-15, D-16)

    // Peak values and velocities in normalized [0.0, 1.0] space (matching FFT output).
    // Winamp canonical: config_sa_peak_falloff=1 → spfo=1.1 (draw_sa.cpp t_vx[x] *= spfo)
    private var peakValues: [Float] = Array(repeating: 0, count: 75)
    private var peakVelocity: [Float] = Array(repeating: 0, count: 75)

    // MARK: - Rust handle

    // Rust ManzoHandle pointer — set by AppDelegate after manzo_open succeeds.
    // Type matches AppDelegate.manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>?
    var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    // MARK: - Render loop (SPEC-04)

    // DispatchSourceTimer at ~60fps on a dedicated .userInteractive queue.
    // CADisplayLink(target:selector:) is iOS-only; on macOS use DispatchSourceTimer.
    private var renderSource: DispatchSourceTimer?

    // MARK: - Initialization

    init() {
        // Obtain the default Metal device.
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("MANZO Phase 7: MTLCreateSystemDefaultDevice() returned nil — Metal not available")
        }
        // Frame: 225 × 32 pt (D-01: 75 bars × 3 pt/bar, 16 height levels × 2 pt/level)
        super.init(frame: NSRect(x: 0, y: 0, width: 225, height: 32), device: device)
        self.device = device

        configureMetal()
        setupBuffers()
        setupShaders()

        NSLog("MANZO Phase 7: ManzoSpectrumView initialized — 225×32 pt, .rgba16Float, displayP3")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Metal Configuration

    private func configureMetal() {
        // CRITICAL (SPEC-01 / spike 010 landmine):
        // MTKView.colorPixelFormat does NOT configure the CAMetalLayer directly on macOS
        // when using a manual render loop — set CAMetalLayer fields explicitly.
        guard let metalLayer = self.layer as? CAMetalLayer else {
            fatalError("MANZO Phase 7: MTKView.layer is not a CAMetalLayer")
        }
        // .rgba16Float: supports values > 1.0 for HDR bloom highlights (spike 011).
        // Setting on CAMetalLayer directly ensures the drawable has the correct format
        // regardless of what MTKView's internal state tracks.
        metalLayer.pixelFormat = .rgba16Float
        // Explicit P3 colorspace — silent sRGB fallback if omitted (spike 010 landmine).
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        // EDR: values slightly > 1.0 render as true HDR highlights on ProMotion displays.
        metalLayer.wantsExtendedDynamicRangeContent = true

        // MTKView configuration: disable automatic rendering — we drive the loop ourselves.
        self.isPaused = true
        self.enableSetNeedsDisplay = false

        // Transparent background so bodyView chrome shows through the edges.
        self.clearColor = MTLClearColorMake(0, 0, 0, 0)

        // Layer: transparent NSView backing.
        // No nested NSVisualEffectView — single-root .behindWindow constraint (spike 007).
        self.wantsLayer = true
        // Do NOT set shouldRasterize on the MTKView — it renders live, not rasterized.
    }

    private func setupBuffers() {
        guard let device = self.device else { return }

        // fftBuffer: 75 Float values — storageModeShared for CPU+GPU access without copy (SPEC-02).
        fftBuffer = device.makeBuffer(length: 75 * MemoryLayout<Float>.stride, options: .storageModeShared)!
        // Zero-initialize: shows a flat spectrum until real FFT data arrives from Rust.
        memset(fftBuffer.contents(), 0, 75 * MemoryLayout<Float>.stride)

        // barVertexBuffer: 75 bars × 6 vertices × 4 floats (16 bytes each).
        barVertexBuffer = device.makeBuffer(
            length: 75 * 6 * 4 * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )!

        // peakVertexBuffer: 75 peak dots × 6 vertices × 4 floats.
        peakVertexBuffer = device.makeBuffer(
            length: 75 * 6 * 4 * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )!
    }

    private func setupShaders() {
        guard let device = self.device else { return }

        // Load the default Metal library — Spectrum.metal is compiled into it by Xcode.
        guard let library = device.makeDefaultLibrary() else {
            fatalError("MANZO Phase 7: makeDefaultLibrary() returned nil — Spectrum.metal not compiled")
        }

        guard let barVertexFn   = library.makeFunction(name: "barVertex"),
              let barFragmentFn  = library.makeFunction(name: "barFragment"),
              let peakVertexFn  = library.makeFunction(name: "peakVertex"),
              let peakFragmentFn = library.makeFunction(name: "peakFragment") else {
            fatalError("MANZO Phase 7: one or more shader functions not found in default library")
        }

        // Bar pipeline: SDF bloom, additive blending for glow accumulation (src*srcAlpha + dst*1).
        let barDesc = MTLRenderPipelineDescriptor()
        barDesc.vertexFunction   = barVertexFn
        barDesc.fragmentFunction = barFragmentFn
        barDesc.colorAttachments[0].pixelFormat = .rgba16Float
        barDesc.colorAttachments[0].isBlendingEnabled = true
        barDesc.colorAttachments[0].sourceRGBBlendFactor        = .sourceAlpha
        barDesc.colorAttachments[0].destinationRGBBlendFactor   = .one
        barDesc.colorAttachments[0].sourceAlphaBlendFactor      = .sourceAlpha
        barDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        barPipelineState = try! device.makeRenderPipelineState(descriptor: barDesc)

        // Peak pipeline: same additive blending, different shaders (D-16: stronger glow).
        let peakDesc = MTLRenderPipelineDescriptor()
        peakDesc.vertexFunction   = peakVertexFn
        peakDesc.fragmentFunction = peakFragmentFn
        peakDesc.colorAttachments[0].pixelFormat = .rgba16Float
        peakDesc.colorAttachments[0].isBlendingEnabled = true
        peakDesc.colorAttachments[0].sourceRGBBlendFactor        = .sourceAlpha
        peakDesc.colorAttachments[0].destinationRGBBlendFactor   = .one
        peakDesc.colorAttachments[0].sourceAlphaBlendFactor      = .sourceAlpha
        peakDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        peakPipelineState = try! device.makeRenderPipelineState(descriptor: peakDesc)
    }

    // MARK: - Render Loop Start/Stop (SPEC-04)

    // Call this from AppDelegate after manzo_open + manzo_play succeeds.
    // CADisplayLink runs on a dedicated background thread — main thread is never blocked by GPU work.
    func startRenderLoop() {
        guard renderSource == nil else { return }
        if commandQueue == nil, let device = self.device {
            commandQueue = device.makeCommandQueue()
        }
        let src = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "ManzoSpectrumRender", qos: .userInteractive)
        )
        src.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(2))
        src.setEventHandler { [weak self] in self?.displayLinkFired() }
        src.resume()
        renderSource = src
        NSLog("MANZO Phase 7: render loop started at 60fps on background queue")
    }

    func stopRenderLoop() {
        renderSource?.cancel()
        renderSource = nil
        NSLog("MANZO Phase 7: render loop stopped")
    }

    // MARK: - Per-Frame Render

    private func displayLinkFired() {
        // 1. Read FFT data from Rust core into the shared MTLBuffer.
        //    manzo_get_spectrum writes 75 floats into fftBuffer.contents() in normalized [0.0, 1.0].
        //    On Apple Silicon: this is a plain ARM STORE into unified physical RAM — no copy (SPEC-02).
        let fftPtr = fftBuffer.contents().assumingMemoryBound(to: Float.self)
        // Guard nil handle: AppDelegate nils this before manzo_close, so no dangling-pointer access.
        if let handle = manzoHandle {
            manzo_get_spectrum(handle, fftPtr, 75)
        }
        // If handle is nil: fftBuffer keeps its last values; peaks decay to zero naturally.

        // 2. Update peak-hold state (D-15: snap up immediately if fft > peak, else accelerating decay).
        //    Winamp draw_sa.cpp: t_vx[x] *= spfo; t_bx[x] -= (int)t_vx[x]
        //    config_sa_peak_falloff = 1 → spfo = 1.1f 
        let spfo: Float = 1.1
        for i in 0..<75 {
            let fftVal = fftPtr[i]
            if fftVal > peakValues[i] {
                // Snap up: bar has risen above last peak. Reset falloff velocity.
                peakValues[i] = fftVal
                peakVelocity[i] = 3.0 / 256.0  // initial velocity (D-15 pattern)
            } else {
                // Accelerating decay: velocity multiplies each tick (exponential feel).
                peakVelocity[i] *= spfo
                peakValues[i] = max(0.0, peakValues[i] - peakVelocity[i])
            }
        }

        // 3. Build vertex buffers for bars and peak dots.
        buildBarVertices()
        buildPeakVertices()

        // 4. Encode and submit the GPU render.
        render()
    }

    // MARK: - Vertex Building

    // Bar vertex buffer: 75 bars × 6 vertices, each vertex = [ndcX, ndcY, barIndex, barHeight].
    // Quads extended ±6 pt (3σ) on all sides so the SDF fragment can compute the full bloom halo.
    private func buildBarVertices() {
        let ptr = barVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        let viewW: Float = 225.0
        let viewH: Float = 32.0
        let sigma: Float = 2.0          // SDF bloom sigma for bars (spike 011)
        let extend: Float = 3.0 * sigma  // 6.0 pt extension on all sides

        // Re-read fftBuffer here so vertex data matches what was just written.
        let fftPtr = fftBuffer.contents().assumingMemoryBound(to: Float.self)

        var vtxIdx = 0
        for bar in 0..<75 {
            let barH = fftPtr[bar]  // normalized height [0.0, 1.0]

            // Bar geometry in pt (bottom-left origin, Metal NDC convention: y=0 at bottom).
            let barWidthPt: Float = 2.0
            let gapPt: Float = 1.0
            let xLeft   = Float(bar) * (barWidthPt + gapPt)
            let xRight  = xLeft + barWidthPt
            let yBottom: Float = 0.0
            let yTop    = barH * viewH  // bar top in pts

            // Extend all sides by 6 pt for the bloom halo.
            let xl = xLeft   - extend
            let xr = xRight  + extend
            let yb = yBottom - extend
            let yt = yTop    + extend

            // Convert to NDC: x: [0,225]→[-1,1], y: [0,32]→[-1,1]
            func ndcX(_ x: Float) -> Float { (x / viewW) * 2.0 - 1.0 }
            func ndcY(_ y: Float) -> Float { (y / viewH) * 2.0 - 1.0 }

            // Two triangles (6 vertices) forming a quad.
            // Per vertex: [ndcX, ndcY, barIndex, barHeight] = 4 floats.
            let bi = Float(bar)
            let verts: [(Float, Float, Float, Float)] = [
                (ndcX(xl), ndcY(yb), bi, barH),  // bottom-left
                (ndcX(xr), ndcY(yb), bi, barH),  // bottom-right
                (ndcX(xl), ndcY(yt), bi, barH),  // top-left
                (ndcX(xr), ndcY(yb), bi, barH),  // bottom-right (tri 2)
                (ndcX(xr), ndcY(yt), bi, barH),  // top-right
                (ndcX(xl), ndcY(yt), bi, barH),  // top-left
            ]
            for v in verts {
                ptr[vtxIdx + 0] = v.0
                ptr[vtxIdx + 1] = v.1
                ptr[vtxIdx + 2] = v.2
                ptr[vtxIdx + 3] = v.3
                vtxIdx += 4
            }
        }
    }

    // Peak dot vertex buffer: 75 dots × 6 vertices.
    // Each dot is 1-pt tall × 2-pt wide. Extended by 3×σ (σ=4 → 12 pt) for stronger bloom (D-16).
    private func buildPeakVertices() {
        let ptr = peakVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        let viewW: Float = 225.0
        let viewH: Float = 32.0
        let sigma: Float = 4.0           // peak dots: σ×2.0 = stronger glow (D-16)
        let extend: Float = 3.0 * sigma  // 12.0 pt extension

        var vtxIdx = 0
        for bar in 0..<75 {
            let peakH = peakValues[bar]

            let barWidthPt: Float = 2.0
            let gapPt: Float = 1.0
            let xLeft  = Float(bar) * (barWidthPt + gapPt)
            let xRight = xLeft + barWidthPt
            let yDot   = peakH * viewH  // 1-pt dot centered at peak level in pt

            // ±0.5 pt for 1-pt dot height; plus the full bloom extension on all sides.
            let xl = xLeft  - extend
            let xr = xRight + extend
            let yb = yDot   - 0.5 - extend
            let yt = yDot   + 0.5 + extend

            func ndcX(_ x: Float) -> Float { (x / viewW) * 2.0 - 1.0 }
            func ndcY(_ y: Float) -> Float { (y / viewH) * 2.0 - 1.0 }

            let bi = Float(bar)
            let verts: [(Float, Float, Float, Float)] = [
                (ndcX(xl), ndcY(yb), bi, peakH),
                (ndcX(xr), ndcY(yb), bi, peakH),
                (ndcX(xl), ndcY(yt), bi, peakH),
                (ndcX(xr), ndcY(yb), bi, peakH),
                (ndcX(xr), ndcY(yt), bi, peakH),
                (ndcX(xl), ndcY(yt), bi, peakH),
            ]
            for v in verts {
                ptr[vtxIdx + 0] = v.0
                ptr[vtxIdx + 1] = v.1
                ptr[vtxIdx + 2] = v.2
                ptr[vtxIdx + 3] = v.3
                vtxIdx += 4
            }
        }
    }

    // MARK: - Render

    private func render() {
        // Threat model T-07-05: guard all optionals — render() returns early on nil (no crash).
        // Build MTLRenderPassDescriptor manually from drawable.texture instead of using
        // currentRenderPassDescriptor — the MTKView property internally calls currentDrawable
        // a second time, which triggers "addPresentedHandler cannot be called after drawable
        // has been presented" when isPaused=true with a manual render loop.
        guard let drawable = currentDrawable,
              let cmdQueue = commandQueue else { return }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture     = drawable.texture
        descriptor.colorAttachments[0].loadAction  = .clear
        descriptor.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store

        guard let cmdBuf  = cmdQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        // Pass 1: Spectrum bars with SDF Gaussian bloom (SPEC-03).
        if let barPSO = barPipelineState {
            encoder.setRenderPipelineState(barPSO)
            encoder.setVertexBuffer(barVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 75 * 6)
        }

        // Pass 2: Peak-hold dots with stronger glow (D-16, σ=4.0).
        if let peakPSO = peakPipelineState {
            encoder.setRenderPipelineState(peakPSO)
            encoder.setVertexBuffer(peakVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 75 * 6)
        }

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - MTKView lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Create commandQueue lazily when device is confirmed available at window attachment.
        if commandQueue == nil, let device = self.device {
            commandQueue = device.makeCommandQueue()
            NSLog("MANZO Phase 7: commandQueue created on viewDidMoveToWindow")
        }
    }
}
