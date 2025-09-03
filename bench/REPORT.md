# Task 5: Benchmarking & Stability - Performance Analysis

## FPS/Latency Limiting Factors

Based on dual-camera benchmarking with e-CAM25_CUONX (AR0234 sensors) on Jetson Orin Nano:

### Confirmed Performance Results
- **1280x720@70fps Target**: Achieved 29 FPS avg (41% of target)
- **CPU Bottleneck**: 95% avg usage, 100% peaks during encoding  
- **GPU Underutilized**: 3% usage (software encoder doesn't use GPU)
- **Thermal Stable**: 48-54°C range, no thermal limiting
- **Memory Bandwidth**: 13% usage, not saturated

### Primary Bottlenecks
- **Software Encoding (x264enc)**: Primary limitation - CPU-bound H.264 encoding
- **Pipeline Complexity**: NVMM → nvvidconv → I420 → x264enc conversion overhead
- **Frame Delivery Variance**: Camera 1 shows higher instability (6.9-35.3 FPS range vs Camera 0: 13.8-35.1 FPS)

### Measured Performance Impact  
- **Target 70 FPS**: Achieved ~29 FPS (58% performance gap)
- **FPS Variance**: Camera 0 variance=10.92, Camera 1 variance=21.64
- **File Output**: ~27MB total for 60s dual recording (consistent bitrate)
- **System Load**: CPU maxed, GPU idle, memory/thermal headroom available

### Root Cause Analysis
Software H.264 encoding creates the primary bottleneck. The Jetson's CPU cores are fully saturated doing compression work while the GPU encoding units remain unused. This explains the consistent ~30 FPS ceiling regardless of target framerate.

### Recommendations
1. **Hardware H.264 encoding (nvenc)** - Would eliminate CPU bottleneck
2. **Reduce pipeline complexity** - Direct UYVY→H.264 without I420 conversion
3. **Lower target framerates** - 30 FPS profiles would match actual capability
4. **Dual-stream optimization** - Investigate camera synchronization for reduced variance