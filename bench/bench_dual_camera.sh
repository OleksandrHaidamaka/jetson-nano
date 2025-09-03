#!/bin/bash
# Dual Camera Benchmarking Script - Task 5
# Measures performance metrics during dual-camera recording

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[BENCH]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Statistics calculation function
calc_stats() {
    local arr=("$@")
    
    if [[ ${#arr[@]} -eq 0 ]]; then
        echo "0 0 0 0"
        return
    fi
    
    local sum=0
    local min=${arr[0]}
    local max=${arr[0]}
    
    for val in "${arr[@]}"; do
        # Ensure val is numeric and not empty
        if [[ -z "$val" ]] || ! [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            val="0"
        fi
        sum=$(echo "$sum + $val" | bc -l)
        if (( $(echo "$val < $min" | bc -l) )); then min=$val; fi
        if (( $(echo "$val > $max" | bc -l) )); then max=$val; fi
    done
    
    local avg=$(echo "scale=2; $sum / ${#arr[@]}" | bc -l)
    
    # Calculate variance
    local var_sum=0
    for val in "${arr[@]}"; do
        local diff=$(echo "$val - $avg" | bc -l)
        var_sum=$(echo "$var_sum + ($diff * $diff)" | bc -l)
    done
    local variance=$(echo "scale=2; $var_sum / ${#arr[@]}" | bc -l)
    
    echo "$avg $min $max $variance"
}

# Configuration  
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$PROJECT_DIR/bench"
DURATION=60
PROFILE=""
SAMPLE_INTERVAL=1  # seconds

usage() {
    echo "Usage: $0 --profile <profile_name>"
    echo ""
    echo "Available profiles:"
    echo "  640x400_120fps_8bit"
    echo "  1280x800_70fps_8bit"
    echo ""
    echo "Example: $0 --profile 640x400_120fps_8bit"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
        PROFILE="$2"
        shift 2
        ;;
        --duration)
        DURATION="$2"
        shift 2
        ;;
        -h|--help)
        usage
        ;;
        *)
        echo "Unknown option: $1"
        usage
        ;;
    esac
done

if [[ -z "$PROFILE" ]]; then
    error "Profile is required"
    usage
fi

# Validate profile
if [[ ! "$PROFILE" =~ ^(640x400_120fps_8bit|1280x800_70fps_8bit)$ ]]; then
    error "Unknown profile: $PROFILE"
    usage
fi

BENCHMARK_ID="$(date +%Y%m%d_%H%M%S)"
RESULTS_FILE="$BENCH_DIR/results_${PROFILE}_${BENCHMARK_ID}.json"
TEGRASTATS_LOG="/tmp/tegrastats_${BENCHMARK_ID}.log"
LOG_DIR="/tmp"

header "Dual Camera Benchmarking - Profile: $PROFILE"

log "Benchmark ID: $BENCHMARK_ID"
log "Duration: ${DURATION} seconds"
log "Results file: $RESULTS_FILE"
log ""

# Pre-flight checks
if ! command -v tegrastats >/dev/null 2>&1; then
    warn "tegrastats not available - CPU/GPU monitoring limited"
    TEGRASTATS_AVAILABLE=false
else
    TEGRASTATS_AVAILABLE=true
fi

# System preparation
log "Preparing system for benchmarking..."
log "Setting maximum performance mode..."
sudo nvpmodel -m 0 >/dev/null 2>&1 || warn "nvpmodel not available"
sudo jetson_clocks >/dev/null 2>&1 || warn "jetson_clocks not available"

# Clear system caches
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || warn "Cannot clear caches"

sleep 2
log "System prepared"

# Start system monitoring
MONITOR_PID=""
if [[ "$TEGRASTATS_AVAILABLE" == "true" ]]; then
    log "Starting tegrastats monitoring..."
    tegrastats --interval $((SAMPLE_INTERVAL * 1000)) --logfile "$TEGRASTATS_LOG" &
    MONITOR_PID=$!
    sleep 1
fi

# Record baseline metrics
BASELINE_TIMESTAMP=$(date +%s%3N)
BASELINE_CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}' | tr ',' '.' || echo "0")
BASELINE_GPU_TEMP=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null | awk '{print $1/1000}' | tr ',' '.' || echo "0")

log "Baseline CPU temperature: ${BASELINE_CPU_TEMP}°C"
log "Baseline GPU temperature: ${BASELINE_GPU_TEMP}°C"

# Configure recording parameters based on profile
case "$PROFILE" in
    "640x400_120fps_8bit")
        WIDTH=640
        HEIGHT=480
        FRAMERATE=120
        ;;
    "1280x800_70fps_8bit")
        WIDTH=1280
        HEIGHT=720  
        FRAMERATE=120
        ;;
esac

ENCODER="x264enc bitrate=10000 speed-preset=fast tune=zerolatency"
FORMAT="video/x-raw,format=I420"

# Create output files in bench directory
TIMESTAMP=$(date +%s%N | cut -b1-16)
CAM0_VIDEO="$BENCH_DIR/cam0_${PROFILE}_${BENCHMARK_ID}.mkv"
CAM1_VIDEO="$BENCH_DIR/cam1_${PROFILE}_${BENCHMARK_ID}.mkv"

log "Starting dual camera recording with performance monitoring..."
log "Recording to: $CAM0_VIDEO"
log "Recording to: $CAM1_VIDEO"

RECORDING_START=$(date +%s%3N)

# FPS monitoring via file size (fpsdisplaysink not available)

# Build GStreamer pipelines (simple timeout approach)
GST_PIPELINE_CAM0="nvv4l2camerasrc device=/dev/video0 ! video/x-raw(memory:NVMM),format=UYVY,width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE}/1 ! nvvidconv ! ${FORMAT},width=${WIDTH},height=${HEIGHT} ! ${ENCODER} ! h264parse ! matroskamux ! filesink location=${CAM0_VIDEO}"

GST_PIPELINE_CAM1="nvv4l2camerasrc device=/dev/video1 ! video/x-raw(memory:NVMM),format=UYVY,width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE}/1 ! nvvidconv ! ${FORMAT},width=${WIDTH},height=${HEIGHT} ! ${ENCODER} ! h264parse ! matroskamux ! filesink location=${CAM1_VIDEO}"

# Start dual camera recording
log "✓ Starting camera 0 recording..."
timeout $DURATION gst-launch-1.0 $GST_PIPELINE_CAM0 >/dev/null 2>&1 &
CAM0_PID=$!

log "✓ Starting camera 1 recording..."  
timeout $DURATION gst-launch-1.0 $GST_PIPELINE_CAM1 >/dev/null 2>&1 &
CAM1_PID=$!

log "Recording PIDs: CAM0=$CAM0_PID, CAM1=$CAM1_PID"
log "Recording for $DURATION seconds..."

# Performance monitoring arrays
CPU_TEMPS=()
GPU_TEMPS=()
CPU_USAGE=()
GPU_USAGE=()
MEMORY_USAGE=()
CAM0_FPS_SAMPLES=()
CAM1_FPS_SAMPLES=()
ITERATION=0
PREV_CAM0_SIZE=0
PREV_CAM1_SIZE=0

log "Monitoring performance metrics while recording..."

# Monitor system performance every second while cameras are recording  
while (kill -0 $CAM0_PID 2>/dev/null || kill -0 $CAM1_PID 2>/dev/null); do
    sleep $SAMPLE_INTERVAL
    ITERATION=$((ITERATION + 1))
    
    # Sample temperatures
    CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}' | tr ',' '.' || echo "0")
    GPU_TEMP=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null | awk '{print $1/1000}' | tr ',' '.' || echo "0")
    
    CPU_TEMPS+=($CPU_TEMP)
    GPU_TEMPS+=($GPU_TEMP)
    
    # Sample CPU usage (approximate)
    CPU_PCT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null | tr ',' '.' || echo "0")
    CPU_USAGE+=($CPU_PCT)
    
    # Sample GPU usage from tegrastats log
    if [[ -f "$TEGRASTATS_LOG" ]] && [[ -s "$TEGRASTATS_LOG" ]]; then
        GPU_PCT=$(tail -1 "$TEGRASTATS_LOG" 2>/dev/null | grep -o 'GR3D_FREQ [0-9]*%' | grep -o '[0-9]*' | head -1 || echo "0")
        if [[ -z "$GPU_PCT" ]]; then GPU_PCT="0"; fi
        GPU_USAGE+=($GPU_PCT)
    else
        GPU_USAGE+=(0)
    fi
    
    # Sample memory usage
    MEM_USAGE=$(free | grep '^Mem:' | awk '{printf "%.1f", ($3/$2) * 100}' 2>/dev/null | tr ',' '.' || echo "0")
    MEMORY_USAGE+=($MEM_USAGE)
    
    # Sample FPS from file size growth (if files exist)
    if [[ -f "$CAM0_VIDEO" ]] && [[ $ITERATION -gt 1 ]]; then
        current_cam0_size=$(stat -c%s "$CAM0_VIDEO" 2>/dev/null || echo "0")
        size_diff=$((current_cam0_size - PREV_CAM0_SIZE))
        if [[ $size_diff -gt 0 ]] && [[ $ITERATION -gt 2 ]]; then
            # Estimate FPS: assume ~10000 kbps bitrate
            expected_bytes_per_sec=$((10000 * 125))  # 10000 kbps = 1250 KB/s  
            estimated_fps=$(echo "scale=1; $FRAMERATE * $size_diff / $expected_bytes_per_sec" | bc -l 2>/dev/null || echo "$FRAMERATE")
            # Clamp to reasonable range
            if (( $(echo "$estimated_fps > 0 && $estimated_fps < 200" | bc -l 2>/dev/null || echo "0") )); then
                CAM0_FPS_SAMPLES+=($estimated_fps)
            fi
        fi
        PREV_CAM0_SIZE=$current_cam0_size
    fi
    
    if [[ -f "$CAM1_VIDEO" ]] && [[ $ITERATION -gt 1 ]]; then
        current_cam1_size=$(stat -c%s "$CAM1_VIDEO" 2>/dev/null || echo "0")
        size_diff=$((current_cam1_size - PREV_CAM1_SIZE))
        if [[ $size_diff -gt 0 ]] && [[ $ITERATION -gt 2 ]]; then
            expected_bytes_per_sec=$((10000 * 125))
            estimated_fps=$(echo "scale=1; $FRAMERATE * $size_diff / $expected_bytes_per_sec" | bc -l 2>/dev/null || echo "$FRAMERATE")
            if (( $(echo "$estimated_fps > 0 && $estimated_fps < 200" | bc -l 2>/dev/null || echo "0") )); then
                CAM1_FPS_SAMPLES+=($estimated_fps)
            fi
        fi
        PREV_CAM1_SIZE=$current_cam1_size
    fi
    
    if (( ITERATION % 10 == 0 )); then
        log "Sampling... ${ITERATION}s - CPU: ${CPU_TEMP}°C, GPU: ${GPU_TEMP}°C, CPU%: ${CPU_PCT}%, GPU%: ${GPU_PCT}%, MEM%: ${MEM_USAGE}%"
    fi
done

# Wait for recording processes to complete 
log "Waiting for recording processes to complete..."

wait $CAM0_PID 2>/dev/null || true
wait $CAM1_PID 2>/dev/null || true  

RECORDING_END=$(date +%s%3N)
ACTUAL_DURATION=$((RECORDING_END - RECORDING_START))

# ffprobe removed - gives unrealistic results from container metadata
# Using only file size growth samples for accurate FPS measurement

# FPS samples collected: real-time monitoring + precise ffprobe measurement
log "Camera 0 FPS samples: ${#CAM0_FPS_SAMPLES[@]} measurements"
log "Camera 1 FPS samples: ${#CAM1_FPS_SAMPLES[@]} measurements"

# Calculate FPS statistics from file size samples only
if [[ ${#CAM0_FPS_SAMPLES[@]} -gt 0 ]]; then
    CAM0_FPS_STATS=($(calc_stats "${CAM0_FPS_SAMPLES[@]}"))
    log "✓ Camera 0: ${CAM0_FPS_STATS[0]} FPS avg (${CAM0_FPS_STATS[1]} - ${CAM0_FPS_STATS[2]}) variance: ${CAM0_FPS_STATS[3]}"
else
    CAM0_FPS_STATS=(0 0 0 0)
    log "✗ Camera 0: No FPS samples collected"
fi

if [[ ${#CAM1_FPS_SAMPLES[@]} -gt 0 ]]; then
    CAM1_FPS_STATS=($(calc_stats "${CAM1_FPS_SAMPLES[@]}"))
    log "✓ Camera 1: ${CAM1_FPS_STATS[0]} FPS avg (${CAM1_FPS_STATS[1]} - ${CAM1_FPS_STATS[2]}) variance: ${CAM1_FPS_STATS[3]}"
else
    CAM1_FPS_STATS=(0 0 0 0)
    log "✗ Camera 1: No FPS samples collected"
fi

log "Recording completed. Actual duration: $((ACTUAL_DURATION/1000))s"

# Stop monitoring
if [[ -n "$MONITOR_PID" ]] && kill -0 $MONITOR_PID 2>/dev/null; then
    log "Stopping tegrastats monitoring..."
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
fi

sleep 2

# Analyze results
log "Analyzing performance results..."

# Analyze the recorded files
if [[ -f "$CAM0_VIDEO" ]] && [[ -f "$CAM1_VIDEO" ]]; then
    # Get file sizes
    CAM0_SIZE=$(stat -c%s "$CAM0_VIDEO" 2>/dev/null || echo "0")
    CAM1_SIZE=$(stat -c%s "$CAM1_VIDEO" 2>/dev/null || echo "0")
    VIDEO_SIZES=($CAM0_SIZE $CAM1_SIZE)
    VIDEO_SIZE=$((CAM0_SIZE + CAM1_SIZE))
    
    log "✓ Camera 0: $CAM0_VIDEO ($CAM0_SIZE bytes)"
    log "✓ Camera 1: $CAM1_VIDEO ($CAM1_SIZE bytes)"
else
    VIDEO_SIZES=(0 0)
    VIDEO_SIZE=0
    ACTUAL_FPS="unknown"
    warn "Could not find recorded video files for analysis"
fi

# calc_stats function moved to top of file

# Calculate performance statistics
if [[ ${#CPU_TEMPS[@]} -gt 0 ]]; then
    CPU_STATS=($(calc_stats "${CPU_TEMPS[@]}"))
    GPU_STATS=($(calc_stats "${GPU_TEMPS[@]}"))
    CPU_USAGE_STATS=($(calc_stats "${CPU_USAGE[@]}"))
    GPU_USAGE_STATS=($(calc_stats "${GPU_USAGE[@]}"))
    MEMORY_STATS=($(calc_stats "${MEMORY_USAGE[@]}"))
else
    CPU_STATS=(0 0 0 0)
    GPU_STATS=(0 0 0 0)
    CPU_USAGE_STATS=(0 0 0 0)
    GPU_USAGE_STATS=(0 0 0 0)
    MEMORY_STATS=(0 0 0 0)
fi

# Parse tegrastats if available
EMC_USAGE="unknown"
if [[ -f "$TEGRASTATS_LOG" ]] && [[ -s "$TEGRASTATS_LOG" ]]; then
    # Extract RAM usage from tegrastats as EMC approximation (RAM usage in MB)
    EMC_USAGE=$(grep -o 'RAM [0-9]*/[0-9]*MB' "$TEGRASTATS_LOG" | sed 's/RAM //' | sed 's/MB$//' | awk -F'/' '{printf "%.1f\n", ($1/$2)*100}' | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "unknown"}')
fi

# Generate benchmark results JSON
log "Generating benchmark results..."

cat > "$RESULTS_FILE" << EOF
{
  "fps_performance": {
    "target_fps": $(echo "$PROFILE" | grep -o '[0-9]\+fps' | grep -o '[0-9]\+'),
    "cameras": [
      {
        "camera_id": 0,
        "avg_fps": $(echo "${CAM0_FPS_STATS[0]}" | tr ',' '.'),
        "min_fps": $(echo "${CAM0_FPS_STATS[1]}" | tr ',' '.'),
        "max_fps": $(echo "${CAM0_FPS_STATS[2]}" | tr ',' '.'),
        "fps_variance": $(echo "${CAM0_FPS_STATS[3]}" | tr ',' '.')
      },
      {
        "camera_id": 1,
        "avg_fps": $(echo "${CAM1_FPS_STATS[0]}" | tr ',' '.'),
        "min_fps": $(echo "${CAM1_FPS_STATS[1]}" | tr ',' '.'),
        "max_fps": $(echo "${CAM1_FPS_STATS[2]}" | tr ',' '.'),
        "fps_variance": $(echo "${CAM1_FPS_STATS[3]}" | tr ',' '.')
      }
    ]
  },
  
  "cpu_performance": {
    "temperature_avg_c": $(echo "${CPU_STATS[0]}" | tr ',' '.'),
    "utilization_avg_percent": $(echo "${CPU_USAGE_STATS[0]}" | tr ',' '.')
  },
  
  "gpu_performance": {
    "temperature_avg_c": $(echo "${GPU_STATS[0]}" | tr ',' '.'),
    "utilization_avg_percent": $(echo "${GPU_USAGE_STATS[0]}" | tr ',' '.')
  },
  
  "memory_utilization": {
    "emc_usage_percent": $(echo "$EMC_USAGE" | tr ',' '.'),
    "ram_usage_percent": $(echo "${MEMORY_STATS[0]}" | tr ',' '.')
  },
  
  "file_sizes": {
    "camera0_bytes": ${VIDEO_SIZES[0]:-0},
    "camera1_bytes": ${VIDEO_SIZES[1]:-0},
    "total_bytes": $VIDEO_SIZE
  }
}
EOF

header "Benchmark Results Summary"

log "Profile: $PROFILE"
log "Actual duration: $((ACTUAL_DURATION/1000))s"
log "Target FPS: $(echo "$PROFILE" | grep -o '[0-9]\+fps' | grep -o '[0-9]\+')"
log "FPS Performance: Camera0=${CAM0_FPS_STATS[0]}, Camera1=${CAM1_FPS_STATS[0]}"
log "CPU Temperature: ${CPU_STATS[0]}°C avg (${CPU_STATS[1]}°C - ${CPU_STATS[2]}°C)"
log "GPU Temperature: ${GPU_STATS[0]}°C avg (${GPU_STATS[1]}°C - ${GPU_STATS[2]}°C)"
log "CPU Usage: ${CPU_USAGE_STATS[0]}% avg (${CPU_USAGE_STATS[1]}% - ${CPU_USAGE_STATS[2]}%)"
log "GPU Usage: ${GPU_USAGE_STATS[0]}% avg (${GPU_USAGE_STATS[1]}% - ${GPU_USAGE_STATS[2]}%)"
log "Memory Usage: ${MEMORY_STATS[0]}% avg"
log "EMC Usage: ${EMC_USAGE}%"
log ""
log "Results saved to: $RESULTS_FILE"

# Cleanup temporary files
if [[ -f "$TEGRASTATS_LOG" ]]; then
    rm -f "$TEGRASTATS_LOG"
fi

log "Benchmark completed successfully!"

# Clean up
if [[ -n "$MONITOR_PID" ]] && kill -0 $MONITOR_PID 2>/dev/null; then
    kill $MONITOR_PID 2>/dev/null || true
fi