import numpy as np
import logging

# Try to import numba for optimization
try:
    from numba import jit, prange, float32, int32, int64, boolean
    NUMBA_AVAILABLE = True
    logger = logging.getLogger(__name__)
    logger.info("Numba available: Using optimized BW conversion functions")
except ImportError:
    NUMBA_AVAILABLE = False
    logger = logging.getLogger(__name__)
    logger.warning("Numba not available: Using standard BW conversion functions")
    # Create dummy decorators for when numba is not available
    def jit(*args, **kwargs):
        def decorator(func):
            return func
        return decorator
    prange = range


class BwConversionMethod:
    """Enumeration of available black and white conversion methods."""
    SIMPLE_THRESHOLD = 1
    ADAPTIVE_THRESHOLD = 2


@jit(nopython=True, cache=True)
def apply_gamma_correction(pixels, gamma_value):
    """
    Apply gamma correction to grayscale image.
    
    Args:
        pixels: Numpy array of grayscale image (0-255)
        gamma_value: Gamma value to apply (typically 0.5-1.0)
    
    Returns:
        Numpy array with gamma correction applied
    """
    # Make a copy to avoid modifying original
    corrected = pixels.copy()
    
    # Scale to 0-1, apply gamma, scale back to 0-255
    max_val = 255.0
    corrected = ((corrected / max_val) ** gamma_value) * max_val
    
    return corrected


@jit(nopython=True, cache=True)
def simple_threshold(pixels, threshold):
    """
    Apply simple global thresholding to a grayscale image.
    
    Args:
        pixels: Numpy array of grayscale image (0-255)
        threshold: Global threshold value (0-255)
    
    Returns:
        Binary numpy array (values 0 or 1)
    """
    return (pixels <= threshold).astype(np.uint8)


# Adaptive thresholding cannot be fully optimized with Numba due to complex operations
# We'll create an optimized helper function
@jit(nopython=True, parallel=True, cache=True)
def _compute_block_means(pixels, block_size):
    """
    Compute mean values for each block in the image.
    Optimized with Numba.
    
    Args:
        pixels: Numpy array of grayscale image (0-255)
        block_size: Size of local blocks for adaptive thresholding
    
    Returns:
        Numpy array of local means
    """
    height, width = pixels.shape
    means = np.zeros((height, width), dtype=np.float32)
    
    half_block = block_size // 2
    
    # Process each pixel
    for y in prange(height):
        for x in range(width):
            # Define block boundaries with proper border handling
            y_start = max(0, y - half_block)
            y_end = min(height, y + half_block + 1)
            x_start = max(0, x - half_block)
            x_end = min(width, x + half_block + 1)
            
            # Compute mean of the block
            block_sum = 0.0
            count = 0
            for by in range(y_start, y_end):
                for bx in range(x_start, x_end):
                    block_sum += pixels[by, bx]
                    count += 1
            
            means[y, x] = block_sum / count
    
    return means


def adaptive_threshold(pixels, block_size, c):
    """
    Apply adaptive thresholding to grayscale image.
    Each pixel is compared to the mean of its surrounding block.
    
    Args:
        pixels: Numpy array of grayscale image (0-255)
        block_size: Size of local blocks (must be odd)
        c: Constant subtracted from mean (can be negative)
    
    Returns:
        Binary numpy array (values 0 or 1)
    """
    # Ensure block size is odd
    if block_size % 2 == 0:
        block_size += 1
    
    # If Numba available, compute means using optimized function
    block_means = _compute_block_means(pixels, block_size)
    
    # Apply threshold: pixel is 1 if it's >= (mean - c)
    return (pixels >= (block_means - c)).astype(np.uint8)


def convert_to_bw(pixels, config):
    """
    Convert a grayscale image to black and white using the specified method.
    
    Args:
        pixels: Numpy array of grayscale image (0-255)
        config: Dictionary containing conversion parameters from display_config
    
    Returns:
        Binary numpy array (values 0 or 1)
    """
    # Get configuration settings
    bw_config = config.get("eink_bw_conversion", {})
    method = bw_config.get("method", BwConversionMethod.SIMPLE_THRESHOLD)
    use_gamma = bw_config.get("use_gamma", False)
    gamma_value = bw_config.get("gamma_value", 0.7)
    threshold = config.get("eink_threshold", 128)
    adaptive_block_size = bw_config.get("adaptive_block_size", 16)
    adaptive_c = bw_config.get("adaptive_c", 5)
    
    # Make sure we're working with a copy
    pixels = pixels.copy()
    
    # Apply gamma correction if enabled
    if use_gamma:
        pixels = apply_gamma_correction(pixels, gamma_value)
    
    # Apply the selected conversion method
    if method == BwConversionMethod.SIMPLE_THRESHOLD:
        return simple_threshold(pixels, threshold)
    elif method == BwConversionMethod.ADAPTIVE_THRESHOLD:
        return adaptive_threshold(pixels, adaptive_block_size, adaptive_c)
    else:
        # Fallback to simple threshold if unknown method
        return simple_threshold(pixels, threshold) 