config = {
    "display": {
        "eink_adaptive_capture": True,  # Enable adaptive refresh rate
        "eink_dithering_enabled": False,
        "eink_dithering_method": 2,  # 1=Floyd-Steinberg, 2=Ordered
        "eink_full_refresh_interval": 15,
        "eink_refresh_interval": 1500,
        "eink_enabled": True,
        "eink_buffer_size": 1,  # Reduced buffer size to save memory
        "eink_threshold": 90,  # Threshold for black/white conversion (0-255)
        "eink_bw_conversion": {
            "method": 1,  # 1=Simple Threshold, 2=Adaptive Threshold
            "use_gamma": True,  # Apply gamma correction before thresholding
            "gamma_value": 0.7,  # Gamma correction value (0.5-1.0, lower = darker)
            "adaptive_block_size": 16,  # Block size for adaptive thresholding (must be odd)
            "adaptive_c": 5  # Constant subtracted from block mean/median (can be negative)
        },
        "dark_mode": False,
        "width": 240,
        "height": 416,
        "font": {
            "primary_font": "fonts/IosevkaTermSlabNerdFont-Bold.ttf",  # Default font for UI elements
            "font_size_small": 12,
            "font_size_normal": 14,
            "font_size_medium": 16,
            "font_size_large": 18,
            "font_size_xlarge": 20
        }
    }
}

# TODO: revisit to see better options
