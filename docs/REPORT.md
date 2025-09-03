# Technical Report: Dual e-CAM25_CUONX Camera System
## Jetson Orin Nano Implementation

### Executive Summary

Successfully implemented a dual-camera recording system for e-CAM25_CUONX CSI cameras on Jetson Orin Nano with software H.264 encoding, comprehensive benchmarking, and ISP configuration management. The system achieves stable ~30 FPS recording with dual cameras despite CPU encoding limitations.

---

## 1. Architecture & Implementation

### 1.1 Recording Pipeline
**Selected: GStreamer with Software H.264 Encoding**

**Actual Pipeline:**
```bash
nvv4l2camerasrc → UYVY → nvvidconv → I420 → x264enc → H.264 → MKV
```

**Key Characteristics:**
- **Encoder**: x264enc (CPU-based software encoding)
- **Performance**: ~30 FPS actual vs 70-120 FPS targets
- **CPU Usage**: 95% average, 100% peaks
- **GPU Usage**: 3% (software encoder doesn't use GPU)
- **Bitrate**: 10000 kbps with fast preset

**Alternative Approaches Considered:**
- **Hardware H.264**: Not available/implemented on this platform
- **Raw Recording**: Impractical storage requirements
- **Lower Bitrate**: Would compromise quality

### 1.2 File Organization
```
./recordings/<deviceId>/<camName>/<camId>/<videoIndex>/
├── video.mkv     # H.264 in Matroska container
└── metadata.json # JSON sidecar with session info
```

**Benefits:**
- Scalable directory structure
- Frame-accurate correlation via timestamps
- Comprehensive metadata framework (mostly placeholders)

---

## 2. Performance Benchmarking

### 2.1 Benchmark Implementation
**Monitoring Method:** Real-time sampling during recording

**Metrics Collected:**
- CPU/GPU temperatures via thermal zones
- CPU/GPU usage via tegrastats and system monitoring
- Memory utilization and EMC usage
- FPS estimation via file size growth analysis
- Frame variance and stability measurements

### 2.2 Measured Results

**1280x720@70fps Target Profile:**
- **Target FPS**: 70
- **Actual FPS**: ~29 (Camera 0: 28.57, Camera 1: 29.49)
- **Performance Gap**: 58% below target
- **CPU Temperature**: 48-54°C (thermal stable)
- **CPU Usage**: 95% average, 100% peaks
- **GPU Usage**: 3% (encoder doesn't use GPU)
- **Memory Usage**: 13% (not saturated)

**Key Findings:**
- **Primary Bottleneck**: Software H.264 encoding (CPU-bound)
- **Thermal Status**: No thermal throttling observed
- **Memory Bandwidth**: Adequate (13% usage)
- **System Stability**: Consistent ~30 FPS ceiling regardless of target

### 2.3 Limiting Factors Analysis

**Primary Bottleneck: Software Encoding**
- x264enc saturates CPU cores with compression work
- GPU encoding units remain unused at 3% utilization
- Consistent ~30 FPS ceiling across all target framerates

**Secondary Factors:**
- **Pipeline Complexity**: NVMM → nvvidconv → I420 → x264enc conversion overhead
- **Frame Delivery Variance**: Camera 1 shows higher instability (variance 21.64 vs 10.92)

**Not Limiting:**
- Memory bandwidth (only 13% utilized)
- Thermal constraints (48-54°C stable range)
- Storage I/O (adequate write speeds observed)

---

## 3. ISP Configuration Management

### 3.1 Manual Configuration Approach
**Strategy**: Static profiles with manual switching

**Implementation:**
- `isp_lowlight.conf`: Optimized for indoor/dim lighting
- `isp_bright.conf`: Optimized for daylight/bright conditions
- `apply_isp_config.sh`: V4L2 control application script
- `record_isp_demo.sh`: Demonstration recording with transitions

### 3.2 Low Light Profile (`isp_lowlight.conf`)
**Optimizations:**
- Exposure: 2000μs (6.4x longer than default)
- Gain: 8x moderate amplification
- Gamma: 200 (lower to reveal shadows)
- White Balance: 3200K (tungsten/indoor lighting)
- Denoise: 10 (higher for gain-induced noise)

**Trade-offs:**
- **Pros**: Better visibility in dark conditions, enhanced color preservation
- **Cons**: Slightly increased noise levels, potential motion blur

### 3.3 Bright Light Profile (`isp_bright.conf`)
**Optimizations:**
- Exposure: 100μs (3.1x shorter than default)
- Gain: 1x (minimum for cleanest signal)
- Gamma: 280 (higher to compress bright tones)
- White Balance: 5600K (daylight standard)
- Sharpness: 25 (enhanced for crisp details)

**Trade-offs:**
- **Pros**: Clean sharp images, preserved highlights, accurate daylight colors
- **Cons**: May slightly underexpose shadow areas

### 3.4 Demonstration Implementation
**ISP Demo Recording**: 60-second clips with configuration transitions
- 0-20s: Default settings baseline
- 20-40s: Applied optimized ISP profile
- 40-60s: Return to defaults for comparison

**Validation**: Visual comparison of ISP effectiveness with timestamped transitions

---

## 4. System Integration

### 4.1 Setup Process
**Idempotent Installation**: `setup.sh` handles complete system configuration
- Automatic e-con driver detection and installation
- Combined DTB creation using fdtoverlay
- Camera enumeration verification
- Diagnostic log generation (probe_logs/)
- 10-second test clip recording

### 4.2 Driver Installation
**Challenge**: Complex device tree overlay management
**Solution**: Combined DTB approach using fdtoverlay to merge base DTB with camera overlay

**Technical Implementation:**
```bash
sudo fdtoverlay -i base.dtb -o dual_camera.dtb 2lane-overlay.dtbo
```

### 4.3 Quality Assurance
**Validation Criteria:**
- Dual cameras enumerated (/dev/video0, /dev/video1)
- Target resolutions supported (640×480, 1280×720)
- H.264 streams playable in standard players
- JSON metadata generation functional
- Performance metrics within expected ranges

---

## 5. Current Limitations & Future Improvements

### 5.1 Performance Limitations
**CPU Bottleneck**: Software encoding limits to ~30 FPS ceiling
**Metadata Placeholders**: Most performance telemetry not fully implemented
**Manual ISP**: No automatic scene adaptation

### 5.2 Recommended Improvements
1. **Hardware H.264 Encoding**: Implement nvenc for sustained high FPS
2. **Real-time Performance Monitoring**: Complete placeholder telemetry implementation
3. **Actual Lens Calibration**: Replace placeholder distortion coefficients
4. **Pipeline Optimization**: Direct UYVY→H.264 encoding without I420 conversion
5. **Auto-adaptive ISP**: Scene detection for automatic profile switching

### 5.3 Production Deployment Considerations
**Robustness Requirements:**
- Process monitoring and automatic restart
- Storage management and cleanup
- Remote diagnostics capability

**Performance Scaling:**
- Extended duration testing
- Thermal management for continuous operation
- Multi-camera expansion planning

---

## 6. Deliverables Summary

### 6.1 Core Components
**Setup & Configuration:**
- `setup.sh`: Idempotent system setup with driver installation
- `setup.md`: Technical documentation with setup rationale

**Recording System:**
- `recorder/record_dual.sh`: Dual-camera recording with JSON metadata
- `recorder/README.md`: Performance documentation and limitations

**Performance Analysis:**
- `bench/bench_dual_camera.sh`: Real-time performance monitoring
- `bench/REPORT.md`: Bottleneck analysis and findings

**ISP Management:**
- `config/isp_*.conf`: Manual lighting condition presets
- `apply_isp_config.sh`: V4L2 control application
- `record_isp_demo.sh`: ISP demonstration recording

### 6.2 Technical Achievements
**Successful Implementation:**
- Dual-camera concurrent recording at stable ~30 FPS
- Comprehensive JSON metadata framework
- Performance benchmarking with thermal/CPU monitoring
- Idempotent setup process with automatic driver installation
- Manual ISP configuration system with demonstration

**Performance Reality:**
- **Container**: Matroska (.mkv) - Implemented
- **Codec**: H.264 software encoded - Implemented (not hardware accelerated)
- **Profiles**: Limited to ~30 FPS actual performance - CPU bottlenecked
- **Metadata**: Comprehensive framework with placeholder telemetry - Partially implemented
- **Benchmarking**: Full performance analysis - Implemented

### 6.3 Implementation Status
**Fully Functional:**
- Dual-camera recording system
- Performance benchmarking and analysis
- ISP configuration management
- Setup automation and validation

**Placeholder/Future Enhancement:**
- Real-time performance telemetry
- Hardware encoder integration
- Automatic scene adaptation
- Advanced lens calibration

---

## 7. Conclusion

Successfully delivered a working dual-camera recording system with comprehensive performance analysis. While software encoding creates a performance ceiling at ~30 FPS, the system demonstrates stable operation, thorough benchmarking, and a solid foundation for future hardware encoder integration. The implementation prioritizes reliability and comprehensive analysis over raw performance claims.