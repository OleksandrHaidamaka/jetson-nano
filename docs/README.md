# e-CAM25_CUONX Dual Camera Recording System
## Jetson Orin Nano Technical Take-Home Assignment

This project implements a dual-camera recording system for e-CAM25_CUONX CSI cameras on NVIDIA Jetson Orin Nano, producing H.264 video with software encoding and comprehensive JSON metadata for analysis.

## Quick Start

### 1. System Setup
```bash
cd ~/jetson-camera-project
./setup.sh
```

### 2. Driver Installation
```bash
# Automatic driver installation via setup.sh
# If drivers not detected, setup.sh will:
# 1. Install e-con drivers automatically
# 2. Create combined DTB with fdtoverlay
# 3. Update boot configuration
# 4. Require reboot for changes
```

### 3. Verify Camera Detection
```bash
# After reboot, verify cameras
v4l2-ctl --list-devices
v4l2-ctl --list-formats-ext -d /dev/video0
v4l2-ctl --list-formats-ext -d /dev/video1
```

### 4. Record Video
```bash
# Record 60s dual-camera video
./recorder/record_dual.sh --profile 640x400_120fps_8bit
./recorder/record_dual.sh --profile 1280x800_70fps_8bit
```

### 5. Run Benchmarks
```bash
# Benchmark performance
./bench/bench_dual_camera.sh --profile 640x400_120fps_8bit
./bench/bench_dual_camera.sh --profile 1280x800_70fps_8bit
```

## Project Structure

```
jetson-camera-project/
├── drivers/           # Camera driver installation files
├── recorder/          # Recording scripts and applications
├── bench/            # Benchmarking and performance monitoring
├── config/           # ISP configuration files
├── docs/             # Documentation
├── storage/          # Temporary storage utilities
└── probe_logs/       # System probe and verification logs
```

## Recording Profiles

| Profile | Target Resolution | Actual Resolution | Target FPS | Actual FPS | Use Case |
|---------|------------------|------------------|------------|------------|----------|
| 640x400_120fps_8bit | 640×400 | 640×480 | 120 | ~30 | High-speed capture (CPU limited) |
| 1280x800_70fps_8bit | 1280×800 | 1280×720 | 70 | ~30 | High-resolution capture (CPU limited) |

**Performance Note:** Software H.264 encoding (x264enc) limits actual FPS to ~30 due to CPU bottleneck.

## Output Format

### Video Files
- **Container**: Matroska (.mkv)
- **Codec**: H.264 (software encoded with x264enc)
- **Bitrate**: 10000 kbps with fast preset
- **Naming**: `deviceId_camName_camId_0_videoIndex_timestamp.mkv`

### Metadata Files
- **Format**: JSON sidecar files
- **Content**: Recording session info, encoder settings, camera specifications
- **Status**: Most performance data marked as PLACEHOLDER (future enhancement)
- **Naming**: `deviceId_camName_camId_0_videoIndex_timestamp.json`

### Directory Structure
```
/recordings/
├── <deviceId>/
│   └── <camName>/
│       ├── 0/                    # Camera 0 recordings
│       │   └── <videoIndex>/
│       │       ├── video.mkv
│       │       └── metadata.json
│       └── 1/                    # Camera 1 recordings
│           └── <videoIndex>/
│               ├── video.mkv
│               └── metadata.json
```

## ISP Controls

### Low Light Configuration (`config/isp_lowlight.conf`)
- Increased gain range (1.0-16.0)
- Longer exposure times
- Enhanced noise reduction
- Reduced frame rate for stability
- Gamma adjustment for visibility

### Bright Light Configuration (`config/isp_bright.conf`)
- Reduced gain range (1.0-4.0)
- Short exposure times
- Minimal noise reduction
- Full frame rate capability
- Highlight recovery

## Performance Benchmarking

The benchmark script monitors:
- **FPS**: Actual vs target frame rates
- **Thermal**: CPU/GPU temperatures
- **Resource Usage**: CPU, memory, EMC utilization
- **Stability**: Frame rate variance and consistency

Results are saved as JSON files in `bench/results_<profile>.json`.

## Technical Implementation

### GStreamer Pipeline
```bash
nvv4l2camerasrc device=/dev/video0 ! 
video/x-raw(memory:NVMM),format=UYVY,width=W,height=H,framerate=FPS/1 ! 
nvvidconv ! 
video/x-raw,format=I420,width=W,height=H ! 
x264enc bitrate=10000 speed-preset=fast tune=zerolatency ! 
h264parse ! 
matroskamux ! 
filesink location=output.mkv
```

### Key Features
- **Software H.264 Encoding**: CPU-based x264enc encoding (~30 FPS ceiling)
- **Concurrent Recording**: Parallel dual-camera capture with synchronization
- **Metadata Generation**: JSON sidecars with recording session and camera info
- **Performance Benchmarking**: CPU/GPU monitoring during recording
- **ISP Configuration**: Manual presets for different lighting conditions

## System Requirements

- **Platform**: NVIDIA Jetson Orin Nano Super Dev Kit
- **OS**: JetPack 6.1+ (L4T 36.4.0)
- **Power Mode**: MAXN (`nvpmodel -m 0`)
- **Performance**: jetson_clocks enabled
- **Storage**: USB SSD recommended for high bitrate recording

## Troubleshooting

### Cameras Not Detected
1. Check physical connections
2. Verify driver installation: `dmesg | grep -i camera`
3. Confirm L4T version compatibility
4. Check device tree overlay loading

### Recording Failures
1. Verify disk space: `df -h /recordings`
2. Check permissions: `ls -la /recordings`
3. Monitor system resources: `tegrastats`
4. Review GStreamer logs for pipeline errors

### Performance Issues
1. Ensure MAXN power mode: `sudo nvpmodel -m 0`
2. Enable jetson_clocks: `sudo jetson_clocks`
3. Check thermal throttling: `cat /sys/class/thermal/thermal_zone*/temp`
4. Monitor memory usage: `free -h`

## Performance Limitations & Improvements

### Current Limitations
- **CPU Bottleneck**: Software encoding limits to ~30 FPS (vs 70-120 FPS targets)
- **Placeholder Metadata**: Most performance telemetry not implemented
- **Manual ISP**: No automatic scene adaptation

### Potential Improvements
1. **Hardware H.264 Encoding**: Use nvenc for sustained high FPS
2. **Real-time Performance Monitoring**: Implement live CPU/GPU/thermal tracking
3. **Actual Lens Calibration**: Replace placeholder distortion coefficients
4. **Pipeline Optimization**: Direct UYVY→H.264 encoding
5. **Auto-adaptive ISP**: Scene-based parameter adjustment

## Key Files

- `setup.sh`: Idempotent system setup script with driver installation
- `setup.md`: Setup documentation with technical details
- `recorder/record_dual.sh`: Dual-camera recording with JSON metadata
- `recorder/README.md`: Recording system documentation and performance notes
- `bench/bench_dual_camera.sh`: Performance benchmarking with FPS/thermal monitoring
- `bench/REPORT.md`: Performance analysis and bottleneck identification
- `config/isp_*.conf`: Manual ISP presets for different lighting conditions
- `apply_isp_config.sh`: ISP configuration application script
- `config/README.md`: ISP presets documentation and usage
- `record_isp_demo.sh`: ISP configuration demonstration with before/after recording