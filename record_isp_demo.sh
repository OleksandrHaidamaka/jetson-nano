#!/bin/bash

# ISP Demo Recording Script for Task 3.2
# Records 60s dual-camera clip with before/after ISP settings switch

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Configuration
PROJECT_DIR="$HOME/jetson-camera-project"
STORAGE_DIR="$PROJECT_DIR/storage"
SCENARIO="$1"

show_usage() {
    echo "Usage: $0 <scenario>"
    echo "  scenario: lowlight or bright"
    echo ""
    echo "This script records a 60s dual-camera clip demonstrating ISP controls:"
    echo "  0-20s: Default settings"
    echo "  20s: Switch to optimized settings (with timestamp marker)"  
    echo "  20-40s: Optimized settings"
    echo "  40s: Switch back to defaults (with timestamp marker)"
    echo "  40-60s: Default settings again"
}

if [[ $# -ne 1 ]] || [[ ! "$1" =~ ^(lowlight|bright)$ ]]; then
    show_usage
    exit 1
fi

# Create timestamp for unique filenames
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_CAM0="$STORAGE_DIR/isp_demo_${SCENARIO}_cam0_${TIMESTAMP}.mkv"
OUTPUT_CAM1="$STORAGE_DIR/isp_demo_${SCENARIO}_cam1_${TIMESTAMP}.mkv"

header "ISP Demo Recording - $SCENARIO Scenario"

log "Output files:"
log "  Camera 0: $OUTPUT_CAM0"  
log "  Camera 1: $OUTPUT_CAM1"
log ""

# Function to record single camera
record_camera() {
    local device="$1"
    local output_file="$2"
    local cam_num=$(basename "$device" | sed 's/video//')
    
    log "Starting recording for camera $cam_num (${device})..."
    
    # Record 60 seconds with timeline and scenario markers
    gst-launch-1.0 -e nvv4l2camerasrc device="$device" ! \
        "video/x-raw(memory:NVMM), width=1280, height=720, framerate=30/1" ! \
        nvvidconv ! "video/x-raw, format=I420" ! \
        timeoverlay font-desc="Sans Bold 18" ! \
        textoverlay text="00-20s: DEFAULT | 20-40s: ${SCENARIO^^} | 40-60s: DEFAULT" \
            font-desc="Sans Bold 14" valignment=bottom halignment=left ! \
        x264enc bitrate=8000 ! matroskamux ! \
        filesink location="$output_file" > /dev/null 2>&1 &
    
    local pid=$!
    echo "$pid" > /tmp/gst_cam${cam_num}_pid.tmp
    
    return 0
}

# Start recording both cameras
mkdir -p "$STORAGE_DIR"
cd "$STORAGE_DIR"

header "Phase 1: Starting Dual Camera Recording"

record_camera "/dev/video0" "$OUTPUT_CAM0"
record_camera "/dev/video1" "$OUTPUT_CAM1"

sleep 2  # Let recording stabilize

header "Phase 2: Recording Timeline (60 seconds total)"

log "0-20s: Recording with DEFAULT settings..."
log "Current settings: Standard auto exposure and defaults"

# Phase 1: Default settings (0-20 seconds)
sleep 18

log ""
warn "=== 20s TIMESTAMP: Switching to $SCENARIO optimized settings ==="

# Phase 2: Apply optimized settings (20-40 seconds) 
"$PROJECT_DIR/apply_isp_config.sh" "$SCENARIO" both
log "20-40s: Recording with $SCENARIO optimized settings..."

sleep 20

log ""
warn "=== 40s TIMESTAMP: Switching back to DEFAULT settings ==="

# Phase 3: Back to defaults (40-60 seconds)
"$PROJECT_DIR/apply_isp_config.sh" reset both  
log "40-60s: Recording with DEFAULT settings (comparison)..."

sleep 20

header "Phase 3: Stopping Recording"

# Stop both camera recordings gracefully
log "Stopping camera recordings..."

if [[ -f /tmp/gst_cam0_pid.tmp ]]; then
    CAM0_PID=$(cat /tmp/gst_cam0_pid.tmp)
    kill -INT $CAM0_PID 2>/dev/null || true
    wait $CAM0_PID 2>/dev/null || true
    rm /tmp/gst_cam0_pid.tmp
    log "✓ Stopped camera 0 recording"
fi

if [[ -f /tmp/gst_cam1_pid.tmp ]]; then
    CAM1_PID=$(cat /tmp/gst_cam1_pid.tmp)
    kill -INT $CAM1_PID 2>/dev/null || true
    wait $CAM1_PID 2>/dev/null || true
    rm /tmp/gst_cam1_pid.tmp
    log "✓ Stopped camera 1 recording"
fi

# Give pipelines time to flush and close files properly
sleep 2

# Check results
header "Recording Complete - Results"

if [[ -f "$OUTPUT_CAM0" ]] && [[ $(stat -c%s "$OUTPUT_CAM0" 2>/dev/null) -gt 1000000 ]]; then
    CAM0_SIZE=$(stat -c%s "$OUTPUT_CAM0" 2>/dev/null)
    log "✓ Camera 0 clip: $OUTPUT_CAM0 ($CAM0_SIZE bytes)"
else
    warn "✗ Camera 0 recording may have failed"
fi

if [[ -f "$OUTPUT_CAM1" ]] && [[ $(stat -c%s "$OUTPUT_CAM1" 2>/dev/null) -gt 1000000 ]]; then
    CAM1_SIZE=$(stat -c%s "$OUTPUT_CAM1" 2>/dev/null)
    log "✓ Camera 1 clip: $OUTPUT_CAM1 ($CAM1_SIZE bytes)"
else
    warn "✗ Camera 1 recording may have failed"
fi

log ""
log "Timeline markers in the 60s clips:"
log "  00:00-00:20 - Default settings"
log "  00:20-00:40 - $SCENARIO optimized settings"  
log "  00:40-01:00 - Default settings (for comparison)"
log ""
log "ISP Demo recording completed successfully!"
log "Review the clips to see the before/after differences."