# Burst Refresh Mode

## Overview
Burst Refresh is a new refresh mode for e-ink displays that performs 5 partial refreshes in succession. This provides a good balance between speed and image quality, reducing ghosting compared to single partial refresh while still being faster than a full refresh.

## Refresh Modes

OVBuddy now supports three refresh modes for e-ink displays:

### 1. Full Refresh (Default)
- Complete display refresh with flashing
- Slowest but best quality
- No ghosting
- Used automatically for:
  - First successful fetch after startup
  - Error messages
  - Switching from error to success state

### 2. Partial Refresh
- Single partial refresh
- Faster with less flashing
- May have some ghosting
- Good for frequent updates

### 3. Burst Refresh (5x Partial)
- Performs 5 consecutive partial refreshes
- Balanced speed and quality
- Reduces ghosting compared to single partial refresh
- Faster than full refresh (no flashing)
- Recommended for best quality with frequent updates

## Configuration

### Web Interface
1. Navigate to the Configuration section
2. Under Display Settings, find "Refresh Mode"
3. Select one of:
   - Full Refresh
   - Partial Refresh
   - Burst Refresh (5x Partial)
4. If using Partial or Burst refresh, set "E-Ink Partial Update Interval":
   - Twice per second (0.5s) - Most responsive
   - Every second (1s) - Very responsive
   - Every 2 seconds (2s) - Balanced
   - Every 5 seconds (5s) - Conservative
   - Every 10 seconds (10s) - Low frequency
   - Every 15 seconds (15s) - Very low frequency
   - Every 20 seconds (20s) - Minimal updates
5. Save configuration

### config.json
```json
{
  "refresh_mode": "burst",
  "lcd_refresh_rate": 1
}
```

Valid values:
- `refresh_mode`: `"full"`, `"partial"`, `"burst"`
- `lcd_refresh_rate`: For e-ink partial/burst, this is converted from the interval (1-2 FPS)

## Technical Details

### Implementation
When burst mode is enabled and conditions allow partial refresh:
```python
if burst and hasattr(self.epd, "displayPartial"):
    image_buffer = self.epd.getbuffer(display_image)
    for i in range(5):
        self.epd.displayPartial(image_buffer)
```

### When Refresh Modes Apply
- **Always Full Refresh:**
  - First successful fetch after startup
  - Error messages
  - Switching from error to success
  
- **Selected Mode (Full/Partial/Burst):**
  - Normal updates during operation
  - When previous update was successful
  - No error conditions

### Scrolling Support
Destination scrolling is available with both Partial and Burst refresh modes:
- LCD displays: Always available when enabled
- E-ink displays: Available when Partial or Burst mode is selected

## Backward Compatibility

The implementation maintains full backward compatibility:
- Old configs with `use_partial_refresh: true` → `refresh_mode: "partial"`
- Old configs with `use_partial_refresh: false` → `refresh_mode: "full"`
- The `use_partial_refresh` field is still written for compatibility

## Benefits of Burst Refresh

1. **Better Image Quality**: 5 refreshes reduce ghosting significantly
2. **Faster Than Full**: No flashing, quicker than full refresh
3. **Balanced Approach**: Good compromise between speed and quality
4. **E-ink Friendly**: Designed specifically for e-ink display characteristics

## Recommendations

### Refresh Mode
- **High Frequency Updates (< 30s)**: Use Burst or Partial refresh
- **Low Frequency Updates (> 60s)**: Full refresh is fine
- **Best Quality**: Use Burst refresh for optimal balance
- **Maximum Speed**: Use Partial refresh (accepts some ghosting)
- **No Ghosting**: Use Full refresh (slower, with flashing)

### Update Interval (for Partial/Burst)
- **Twice per second (0.5s)**: Best for scrolling text, very responsive
- **Every second (1s)**: Good for frequent updates with smooth scrolling
- **Every 2 seconds (2s)**: Balanced, good for most use cases
- **Every 5-10 seconds (5-10s)**: Conservative, reduces display wear
- **Every 15-20 seconds (15-20s)**: Minimal updates, longest display life

**Note**: More frequent updates may increase e-ink display wear over time. For departure boards that update every 20-60 seconds from the API, setting the partial update interval to 2-5 seconds provides a good balance.

## Testing

To test burst refresh:
1. Set refresh mode to "Burst Refresh (5x Partial)"
2. Set a short refresh interval (e.g., 20 seconds)
3. Observe the display updates
4. You should see 5 quick partial refreshes instead of one
5. Compare image quality with single partial refresh

## Performance

- **Full Refresh**: ~2 seconds (with flashing)
- **Partial Refresh**: ~0.3 seconds (single update)
- **Burst Refresh**: ~1.5 seconds (5 updates, no flashing)

Actual times may vary based on display hardware and content complexity.

