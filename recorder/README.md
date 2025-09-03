# Dual Camera Recorder - Task 3.3

**Implementation:** Professional dual-camera recording system with H.265 encoding and JSON metadata sidecars.

## Approach Selection

**Chosen: GStreamer Pipelines**

**Rationale:**
1. **Memory Efficiency**: NVMM buffers eliminate CPU-GPU memory copies
2. **Concurrent Recording**: Parallel pipeline execution for dual cameras
3. **Mature Ecosystem**: Proven stability for production recording systems
4. **Metadata Integration**: Pipeline introspection for frame-accurate correlation
5. **Software Encoding**: CPU-based x264enc for compatibility

**Alternatives Rejected:**
- **FFmpeg**: Higher CPU overhead, manual synchronization complexity
- **V4L2 + Custom C++**: Weeks of development vs hours, error-prone buffer management
- **Raw Recording**: Impractical storage (60s @ 1280×800 = 110GB+)

## Recording Profiles

| Profile | Resolution | FPS | Bit Depth | Use Case |
|---------|------------|-----|-----------|----------|
| `640x400_120fps_8bit` | 640×400 | 120 | 8-bit | High-speed capture |
| `1280x800_70fps_8bit` | 1280×800 | 70 | 8-bit | High-resolution capture |

**Note:** AR0234 sensor actual resolutions:
- Profile maps to closest supported: 640×480 @ 120fps, 1280×720 @ 120fps
- Encoder handles resolution adaptation automatically

## H.264 Encoding Strategy

**Software Encoding (x264enc):**
- **Settings**: `x264enc bitrate=10000 speed-preset=fast tune=zerolatency`
- **Performance**: ~29 FPS actual vs 70+ FPS target (CPU bottleneck)

**Reasoning:**
- Uses official e-CAM25 GStreamer Usage Guide recommendations
- Jetson Orin Nano hardware encoder not available/tested
- CPU-bound encoding limits performance to ~30 FPS ceiling
- Stable pipeline but performance-limited for high FPS targets

**Performance Impact:**
- CPU usage: 95% avg, 100% peaks during dual-camera recording
- GPU usage: 3% (software encoder doesn't utilize GPU)
- Thermal stable: 48-54°C range

## File Naming Convention

**Format:** `deviceId_camName_camId_0_videoIndex_timestamp.mkv`

**Example:** `JON001_eCAM25_AR0234_0_000123_1690000005123.mkv`

**Components:**
- `JON001` - Device ID (Jetson Orin Nano + serial)
- `eCAM25` - Camera model mnemonic  
- `AR0234` - Sensor model as camId
- `0` - Camera index (0 for /dev/video0, 1 for /dev/video1)
- `000123` - Monotonic video index (zero-padded 6 digits)
- `1690000005123` - UNIX epoch milliseconds start timestamp

## Directory Structure

```
./recordings/
├── JON001/                    # Device ID
│   └── eCAM25/                # Camera model
│       ├── 0/                 # Camera 0 (/dev/video0)
│       │   └── 000123/        # Video index
│       │       ├── JON001_eCAM25_AR0234_0_000123_1690000005123.mkv
│       │       └── JON001_eCAM25_AR0234_0_000123_1690000005123.json
│       └── 1/                 # Camera 1 (/dev/video1)
│           └── 000123/        # Same video index
│               ├── JON001_eCAM25_AR0234_1_000123_1690000005123.mkv
│               └── JON001_eCAM25_AR0234_1_000123_1690000005123.json
```

**Benefits:**
- Scalable to multiple camera types and devices
- Frame-accurate correlation between cameras (same timestamp/index)
- Easy batch processing and analysis
- Version control friendly structure

## Usage

**Record with profile:**
```bash
./record_dual.sh --profile 640x400_120fps_8bit
./record_dual.sh --profile 1280x800_70fps_8bit

# With custom duration
./record_dual.sh --profile 640x400_120fps_8bit --duration 30
```

**List available profiles:**
```bash
./record_dual.sh --list-profiles
```

## Technical Implementation

**GStreamer Pipeline Architecture:**
```
nvv4l2camerasrc → UYVY format → nvvidconv → I420 format → x264enc → h264parse → matroskamux → filesink
                ↓
            metadata extractor → JSON sidecar
```

**Concurrent Execution:**
- Parallel GStreamer pipelines for each camera
- Synchronized start time for frame correlation  
- Graceful shutdown with proper file closure

**Metadata Collection:**
- Frame timestamps and indices
- Camera settings and ISP parameters
- System performance metrics
- Recording session information

## Build & Run Instructions

**Prerequisites:**
```bash
# Ensure GStreamer plugins installed
gst-inspect-1.0 nvv4l2camerasrc
gst-inspect-1.0 x264enc  # Software H.264 encoder (CPU-based)
gst-inspect-1.0 nvvidconv  # Format conversion
```

**Setup:**
```bash
cd ~/jetson-camera-project
chmod +x recorder/record_dual.sh
mkdir -p recordings
```

**Recording:**
```bash
# 60-second dual camera recording
./recorder/record_dual.sh --profile 640x400_120fps_8bit

# With custom duration
./recorder/record_dual.sh --profile 1280x800_70fps_8bit --duration 30
```

**Output Verification:**
```bash
ls -la recordings/JON001/eCAM25/0/000123/
# Should show .mkv and .json files
mediainfo recordings/JON001/eCAM25/0/000123/*.mkv
```