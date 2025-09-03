# e-CAM25_CUONX Dual Camera Setup

**Task 3.1: Camera driver & bring-up**  
**Platform:** Jetson Orin Nano + JetPack 6.1.0  

## Quick Setup

```bash
cd ~/jetson-camera-project
./setup.sh
```

**Script automatically:**
- Installs ffmpeg tools (ffprobe for video analysis)
- Installs e-con drivers (if needed + reboot)
- Creates combined DTB for dual cameras  
- Verifies camera enumeration
- Records 10s test clips

## Technical Solution

**Problem:** Jetson bootloader doesn't apply overlays reliably  
**Solution:** Combined DTB using `fdtoverlay`

```bash
sudo fdtoverlay -i base.dtb -o dual_camera.dtb 2lane-overlay.dtbo
```

## Camera Specs

**Formats:** UYVY, NV16  
**Resolutions:**
- 640×480 @ 120fps
- 1280×720 @ 120fps  
- 1920×1080 @ 65fps
- 1920×1200 @ 60fps

## Hardware Pipeline

```bash
nvv4l2camerasrc → NVMM memory → nvvidconv → x264enc → MKV
```

**Performance:** 9MB clips in ~8 seconds

## Dependencies

**Auto-installed by setup.sh:**
- ffmpeg tools (ffprobe, ffmpeg)
- e-con Systems AR0234 drivers
- Device tree overlays

## Verification

```bash
v4l2-ctl --list-devices  # Should show video0, video1
ls storage/              # Should show 9MB+ clip files
ffprobe --version        # Should show FFmpeg version
```

## Success Criteria

- [x] Automatic driver installation
- [x] 2 cameras enumerated  
- [x] Raw streams: 9.2MB files
- [x] Video clips: 9MB+ H.264 files
- [x] Complete diagnostics in probe_logs/
