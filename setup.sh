#!/bin/bash

# e-CAM25_CUONX Setup Script for Technical Assessment
# Task 3.1: Camera driver & bring-up
# Idempotent script for dual camera bring-up on Jetson Orin Nano

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Configuration
PROJECT_DIR="$HOME/jetson-camera-project"
PROBE_LOGS_DIR="$PROJECT_DIR/probe_logs"
STORAGE_DIR="$PROJECT_DIR/storage"
EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
BASE_DTB="/boot/dtb/kernel_tegra234-p3768-0000+p3767-0005-nv-super.dtb"
OVERLAY_2LANE="/boot/tegra234-p3767-0000-p3768-0000-a0-2lane-ar0234.dtbo"
COMBINED_DTB="/boot/dtb/dual_camera.dtb"

header "Task 3.1: e-CAM25_CUONX Camera Driver & Bring-up"

# Step 1: Verify project structure and dependencies
log "Checking project structure..."
cd "$PROJECT_DIR" || { error "Project directory not found: $PROJECT_DIR"; exit 1; }
mkdir -p "$PROBE_LOGS_DIR" "$STORAGE_DIR"
log "✓ Project directories ready"

# Step 1.5: Install required tools
log "Installing required tools..."
if ! command -v ffprobe >/dev/null 2>&1; then
    log "Installing ffmpeg tools for video analysis..."
    sudo apt update -qq && sudo apt install -y ffmpeg
    if command -v ffprobe >/dev/null 2>&1; then
        log "✓ ffprobe installed successfully"
    else
        error "Failed to install ffprobe"
        exit 1
    fi
else
    log "✓ ffprobe already available"
fi

# Step 2: Check if drivers are already installed
log "Checking e-con Systems drivers..."
if lsmod | grep -q ar0234; then
    log "✓ AR0234 driver module loaded"
else
    warn "AR0234 driver not loaded - checking installation"
    if ls /lib/modules/$(uname -r)/extra/ 2>/dev/null | grep -q ar0234; then
        log "Loading AR0234 module..."
        sudo modprobe ar0234 || warn "Failed to load AR0234 module"
    else
        warn "AR0234 driver not found - attempting automatic installation"
        
        # Check if e-con driver installer exists
        DRIVER_DIR="$PROJECT_DIR/drivers/e-CAM25_CUONX_JETSON_ONX_ONANO_L4T36.4.0_29-MAR-2025_R04"
        INSTALLER="$DRIVER_DIR/install_binaries.sh"
        
        if [[ -f "$INSTALLER" ]]; then
            log "Found e-con driver installer: $INSTALLER"
            log "Running automatic driver installation..."
            
            cd "$DRIVER_DIR"
            chmod +x install_binaries.sh
            
            # Run installer with automatic 2-lane selection (option 1)
            echo "1" | sudo ./install_binaries.sh
            
            log "✓ Driver installation completed"
            warn "REBOOT REQUIRED for driver changes to take effect!"
            echo "Run: sudo reboot"
            echo "Then re-run this script after reboot."
            exit 0
        else
            error "AR0234 driver not installed and installer not found."
            error "Expected installer at: $INSTALLER"
            error "Please install e-con drivers manually first."
            exit 1
        fi
    fi
fi

# Step 3: Check combined DTB configuration (idempotent)
log "Checking boot configuration..."
if [[ -f "$COMBINED_DTB" ]] && grep -q "$COMBINED_DTB" "$EXTLINUX_CONF"; then
    log "✓ Combined DTB already configured"
else
    log "Setting up combined DTB configuration..."
    
    # Create backup if doesn't exist
    if [[ ! -f "${EXTLINUX_CONF}.backup" ]]; then
        sudo cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.backup"
        log "✓ Created backup: ${EXTLINUX_CONF}.backup"
    fi
    
    # Create combined DTB if doesn't exist
    if [[ ! -f "$COMBINED_DTB" ]]; then
        log "Creating combined DTB..."
        sudo fdtoverlay -i "$BASE_DTB" -o "$COMBINED_DTB" "$OVERLAY_2LANE"
        log "✓ Combined DTB created"
    fi
    
    # Update extlinux.conf if needed
    if ! grep -q "$COMBINED_DTB" "$EXTLINUX_CONF"; then
        log "Updating extlinux.conf..."
        TEMP_FILE=$(mktemp)
        while IFS= read -r line; do
            if [[ $line == *"FDT"* ]]; then
                echo "      FDT $COMBINED_DTB" >> "$TEMP_FILE"
            else
                echo "$line" >> "$TEMP_FILE"
            fi
        done < "$EXTLINUX_CONF"
        sudo cp "$TEMP_FILE" "$EXTLINUX_CONF"
        rm "$TEMP_FILE"
        log "✓ Boot configuration updated"
        
        warn "REBOOT REQUIRED for device tree changes!"
        echo "Run: sudo reboot"
        echo "Then re-run this script after reboot."
        exit 0
    fi
fi

# Step 4: Verify camera enumeration
header "Verifying Camera Enumeration"
log "Checking video devices..."
if ls /dev/video* >/dev/null 2>&1; then
    ls -la /dev/video* | tee "$PROBE_LOGS_DIR/video_devices.log"
    
    # Count cameras
    CAMERA_COUNT=$(ls /dev/video* | wc -l)
    if [[ $CAMERA_COUNT -ge 2 ]]; then
        log "✓ Found $CAMERA_COUNT video devices (expecting 2+ for dual cameras)"
    else
        warn "Only found $CAMERA_COUNT video device(s) - dual camera setup may be incomplete"
    fi
else
    error "No video devices found. Check hardware connections and reboot if needed."
    exit 1
fi

# Step 5: Generate probe logs
header "Generating Diagnostic Logs"

log "Collecting boot messages..."
dmesg | grep -E "(tegra|ar0234|video|csi)" > "$PROBE_LOGS_DIR/boot_camera_messages.log" 2>/dev/null || true

log "Collecting V4L2 device information..."
v4l2-ctl --list-devices > "$PROBE_LOGS_DIR/v4l2_devices.log" 2>/dev/null || true

# For each video device, collect detailed info
for video_dev in /dev/video*; do
    if [[ -c "$video_dev" ]]; then
        dev_num=$(basename "$video_dev" | sed 's/video//')
        log "Probing $video_dev..."
        
        v4l2-ctl --device="$video_dev" --all > "$PROBE_LOGS_DIR/camera${dev_num}_caps.log" 2>/dev/null || true
        v4l2-ctl --device="$video_dev" --list-formats-ext > "$PROBE_LOGS_DIR/camera${dev_num}_formats_ext.log" 2>/dev/null || true
        
        # Test stream capability (5 frames)
        log "Testing stream from $video_dev..."
        v4l2-ctl --device="$video_dev" --set-fmt-video=width=1280,height=720,pixelformat=UYVY \
                 --stream-mmap --stream-count=5 \
                 --stream-to="$STORAGE_DIR/test_camera${dev_num}_5frames.raw" \
                 > "$PROBE_LOGS_DIR/camera${dev_num}_stream_test.log" 2>&1 || warn "Stream test failed for $video_dev"
    fi
done

# Step 6: Generate 10s video clips
header "Generating 10-second Video Clips"

for video_dev in /dev/video0 /dev/video1; do
    if [[ -c "$video_dev" ]]; then
        dev_num=$(basename "$video_dev" | sed 's/video//')
        output_file="$STORAGE_DIR/camera${dev_num}_10s_clip.mkv"
        
        log "Recording 10s clip from $video_dev..."
        
        # Simple reliable hardware-accelerated pipeline
        gst-launch-1.0 -e nvv4l2camerasrc device="$video_dev" num-buffers=300 ! \
            "video/x-raw(memory:NVMM), width=1280, height=720" ! \
            nvvidconv ! "video/x-raw, format=I420" ! \
            x264enc bitrate=8000 ! matroskamux ! \
            filesink location="$output_file" \
            > "$PROBE_LOGS_DIR/camera${dev_num}_recording.log" 2>&1
        
        if [[ -f "$output_file" ]] && [[ $(stat -c%s "$output_file" 2>/dev/null) -gt 100000 ]]; then
            file_size=$(stat -c%s "$output_file" 2>/dev/null)
            log "✓ Created clip: $output_file ($file_size bytes)"
        else
            error "Recording failed for $video_dev - check logs"
        fi
    fi
done

# Step 7: Apply performance settings
header "Applying Performance Settings"
log "Setting maximum performance mode..."
sudo jetson_clocks || warn "jetson_clocks failed"
sudo nvpmodel -m 0 || warn "nvpmodel failed"

# Step 8: Summary
header "Setup Complete - Task 3.1 Deliverables"
log "Generated files:"
log "  • setup.sh (this script) - idempotent camera setup"
log "  • probe_logs/ - diagnostic information"
log "  • storage/ - test clips and raw frames"
log ""
log "Camera status:"
v4l2-ctl --list-devices | head -10
log ""
