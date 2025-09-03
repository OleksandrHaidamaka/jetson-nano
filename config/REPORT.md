# ISP Configuration Presets for e-CAM25_CUONX

**Task 3.2 Deliverable:** Two optimized ISP presets for varying lighting conditions.

## Configuration Files

### `isp_lowlight.conf` - Low Light Conditions

**Use Case:** Indoor lighting, evening, dim environments  
**Goal:** Enhance visibility while managing noise

| Setting | Value | What it does |
|---------|-------|--------------|
| `exposure_auto=1` | Manual Mode | Enables precise exposure control |
| `exposure_time_absolute=2000` | 2000μs | Longer exposure to capture more light (vs 312μs default) |
| `gain=8` | 8x amplification | Moderate gain boost for sensitivity (vs 1x default) |
| `brightness=1` | +1 offset | Slight brightness increase for dark scenes |
| `contrast=12` | 12 vs 10 | Enhanced contrast to separate details |
| `saturation=18` | 18 vs 16 | Boosted colors that fade in low light |
| `gamma=200` | 200 vs 220 | Lower gamma reveals shadow details |
| `white_balance_automatic=0` | Manual WB | Precise color control for artificial lighting |
| `white_balance_temperature=3200` | 3200K | Warm temperature for indoor/tungsten lights |
| `denoise=10` | 10 vs 8 | Higher noise reduction for gain-induced noise |
| `sharpness=12` | 12 vs 16 | Reduced sharpening to avoid noise amplification |
| `roi_window_size=24` | 24px vs 8px | Larger ROI for better exposure metering |
| `exposure_compensation=25000` | 25000 vs 16000 | Higher compensation for brightness |

**Trade-offs:**
- **Pros:** Better visibility in dark conditions, enhanced color preservation
- **Cons:** Slightly increased noise levels, potential motion blur from longer exposure

### `isp_bright.conf` - Bright Light Conditions  

**Use Case:** Daylight, outdoor, high-intensity artificial lighting  
**Goal:** Prevent overexposure and preserve highlight details

| Setting | Value | What it does |
|---------|-------|--------------|
| `exposure_auto=1` | Manual Mode | Precise exposure control for bright scenes |
| `exposure_time_absolute=100` | 100μs | Very short exposure to prevent overexposure |
| `gain=1` | 1x (minimum) | Lowest gain for cleanest signal quality |
| `brightness=-2` | -2 offset | Slight darkening to preserve highlights |
| `contrast=8` | 8 vs 10 | Lower contrast maintains tonal range |
| `saturation=12` | 12 vs 16 | Reduced saturation prevents color clipping |
| `gamma=280` | 280 vs 220 | Higher gamma compresses bright tones |
| `white_balance_automatic=0` | Manual WB | Precise daylight color balance |
| `white_balance_temperature=5600` | 5600K | Cool daylight color temperature |
| `denoise=3` | 3 vs 8 | Minimal denoise preserves sharpness |
| `sharpness=25` | 25 vs 16 | Enhanced sharpening for crisp details |
| `roi_window_size=16` | 16px vs 8px | Moderate ROI for bright spot metering |
| `exposure_compensation=8000` | 8000 vs 16000 | Lower compensation prevents overexposure |

**Trade-offs:**
- **Pros:** Clean, sharp images with excellent detail, preserved highlight information, accurate daylight color reproduction
- **Cons:** May slightly underexpose shadow areas

## Usage

**Apply configurations:**
```bash
# Low light scenario
./apply_isp_config.sh lowlight

# Bright light scenario  
./apply_isp_config.sh bright

# Reset to defaults
./apply_isp_config.sh reset
```

**Record before/after demo:**
```bash
# 60-second dual-camera demo with transitions
./record_isp_demo.sh lowlight
./record_isp_demo.sh bright
```

## Technical Notes

**Manual vs Auto Exposure:**
Both presets use `exposure_auto=1` (Manual Mode) instead of `exposure_auto=0` (Full FOV Auto Mode) for precise control over exposure parameters.

**Exposure Time Range:**
- AR0234 supports 1-10000 microseconds
- Default: 312μs
- Low light: 2000μs (6.4x longer)
- Bright: 100μs (3.1x shorter)

**Gain Range:**
- AR0234 supports 1-40x digital gain
- Default: 1x
- Low light: 8x (moderate for quality)
- Bright: 1x (minimum for cleanest signal)

**Color Temperature:**
- 3200K = Tungsten/incandescent indoor lighting
- 5600K = Daylight/flash photography standard

**ROI (Region of Interest):**
Larger ROI windows provide more stable metering but may not react as quickly to lighting changes.
