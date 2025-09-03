#!/bin/bash

# ISP Configuration Application Script for Task 3.2
# Applies real V4L2 controls based on lighting scenario

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
PROJECT_DIR="$HOME/jetson-camera-project"
CONFIG_DIR="$PROJECT_DIR/config"

show_usage() {
    echo "Usage: $0 <config> [device]"
    echo "  config: lowlight, bright, or reset"
    echo "  device: /dev/video0, /dev/video1, or both (default: both)"
    echo ""
    echo "Examples:"
    echo "  $0 lowlight           # Apply low light config to both cameras"
    echo "  $0 bright /dev/video0 # Apply bright config to camera 0 only"
    echo "  $0 reset              # Reset both cameras to defaults"
}

apply_config() {
    local config_file="$1"
    local device="$2"
    
    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file"
        return 1
    fi
    
    if [[ ! -c "$device" ]]; then
        error "Camera device not found: $device"
        return 1
    fi
    
    log "Applying $(basename $config_file) to $device..."
    
    # Parse and apply each control from config file
    while IFS='=' read -r control value; do
        # Skip comments and empty lines
        [[ "$control" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$control" ]] && continue
        
        # Remove inline comments and whitespace
        control=$(echo "$control" | sed 's/[[:space:]]*#.*//' | xargs)
        value=$(echo "$value" | sed 's/[[:space:]]*#.*//' | xargs)
        
        if [[ -n "$control" && -n "$value" ]]; then
            if v4l2-ctl --device="$device" --set-ctrl="$control=$value" 2>/dev/null; then
                log "  ✓ $control = $value"
            else
                warn "  ✗ Failed to set $control = $value"
            fi
        fi
    done < "$config_file"
}

reset_camera() {
    local device="$1"
    
    log "Resetting $device to defaults..."
    
    # Reset to known defaults based on our earlier investigation
    v4l2-ctl --device="$device" --set-ctrl="exposure_auto=0" 2>/dev/null || true      # Auto mode
    v4l2-ctl --device="$device" --set-ctrl="exposure_time_absolute=312" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="gain=1" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="brightness=0" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="contrast=10" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="saturation=16" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="gamma=220" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="white_balance_automatic=1" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="white_balance_temperature=4600" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="sharpness=16" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="denoise=8" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="roi_window_size=8" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="roi_exposure=32896" 2>/dev/null || true
    v4l2-ctl --device="$device" --set-ctrl="exposure_compensation=16000" 2>/dev/null || true
    
    log "✓ Reset $device to defaults"
}

show_current_settings() {
    local device="$1"
    
    log "Current settings for $device:"
    echo "----------------------------------------"
    v4l2-ctl --device="$device" --get-ctrl="exposure_auto,exposure_time_absolute,gain,brightness,contrast,saturation,gamma,white_balance_automatic,white_balance_temperature,sharpness,denoise"
    echo "----------------------------------------"
}

# Main script logic
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

CONFIG="$1"
DEVICE="${2:-both}"

case "$CONFIG" in
    "lowlight")
        CONFIG_FILE="$CONFIG_DIR/isp_lowlight.conf"
        ;;
    "bright")
        CONFIG_FILE="$CONFIG_DIR/isp_bright.conf"
        ;;
    "reset")
        CONFIG_FILE=""
        ;;
    *)
        error "Unknown config: $CONFIG"
        show_usage
        exit 1
        ;;
esac

# Apply to specified devices
if [[ "$DEVICE" == "both" ]]; then
    DEVICES=("/dev/video0" "/dev/video1")
elif [[ "$DEVICE" =~ ^/dev/video[0-9]$ ]]; then
    DEVICES=("$DEVICE")
else
    error "Invalid device: $DEVICE"
    show_usage
    exit 1
fi

for dev in "${DEVICES[@]}"; do
    if [[ "$CONFIG" == "reset" ]]; then
        reset_camera "$dev"
    else
        apply_config "$CONFIG_FILE" "$dev"
    fi
    
    echo ""
    show_current_settings "$dev"
    echo ""
done

log "ISP configuration applied successfully!"
log "You can now test the cameras with different lighting conditions."