#!/bin/bash

# ============================================================================
# VIDEO SETTINGS - SINGLE SOURCE OF TRUTH v2.1.0
# ============================================================================
# This file contains ALL video generation parameters used across all scripts
# YouTube (16:9), Instagram (9:16), and any future formats
#
# CHANGELOG v2.1.0:
# - Added triple-fallback processing system for ultra-reliability
# - Implemented smart threshold detection (150 rotations)
# - Added comprehensive error logging and recovery
# - Enhanced version tracking and monitoring
# - Fixed quality consistency across all track lengths

VIDEO_PROCESSOR_VERSION="2.1.0"
VIDEO_PROCESSOR_BUILD_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================================
# VINYL ROTATION SETTINGS - ULTRA SMOOTH
# ============================================================================
# Slower, more hypnotic rotation for maximum smoothness
# 12 RPM = 5 seconds per rotation (30% slower than before)
VINYL_ROTATION_DURATION=5.0  # seconds per rotation (ultra-smooth)

# Calculate rotation speed (radians per second)
# 2π radians = 360° in VINYL_ROTATION_DURATION seconds
calculate_rotation_speed() {
    if command -v bc >/dev/null 2>&1; then
        echo "scale=8; 2 * 3.14159265359 / $VINYL_ROTATION_DURATION" | bc -l
    else
        awk "BEGIN {printf \"%.8f\", 2 * 3.14159265359 / $VINYL_ROTATION_DURATION}"
    fi
}

# ============================================================================
# VIDEO QUALITY SETTINGS - ULTRA SMOOTH
# ============================================================================
# Optimized for maximum smoothness
VIDEO_PRESET="ultrafast"        # FFmpeg encoding speed
VIDEO_FRAMERATE=30              # fps (higher for ultra-smooth rotation)
AUDIO_BITRATE="320k"           # High quality audio for music
PIXEL_FORMAT="yuv420p"         # Maximum compatibility

# ============================================================================
# RESOLUTION SETTINGS
# ============================================================================
# YouTube 16:9 (HD for performance)
YOUTUBE_WIDTH=1280
YOUTUBE_HEIGHT=720

# Instagram 9:16 (Standard quality - SAME as YouTube)
INSTAGRAM_WIDTH=1080
INSTAGRAM_HEIGHT=1350

# ============================================================================
# PERFORMANCE SETTINGS
# ============================================================================
# Auto-detect CPU cores for optimal FFmpeg threading
get_cpu_cores() {
    sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4"
}

# ============================================================================
# SMART SPINNING OPTIMIZATION
# ============================================================================
# Calculate how many rotation copies needed for given audio duration
calculate_rotations_needed() {
    local audio_duration=$1
    if command -v bc >/dev/null 2>&1; then
        echo "scale=0; ($audio_duration / $VINYL_ROTATION_DURATION) + 1" | bc -l
    else
        awk "BEGIN {printf \"%.0f\", ($audio_duration / $VINYL_ROTATION_DURATION) + 1}"
    fi
}

# ============================================================================
# SMART PROCESSING THRESHOLDS v2.1.0
# ============================================================================
# Optimized thresholds based on real-world testing and failure analysis

# Memory and performance thresholds
MAX_CONCAT_ROTATIONS=150        # Beyond this, use alternative methods
EMERGENCY_FALLBACK_THRESHOLD=200  # Direct generation threshold

# Check system resources before processing
check_system_resources() {
    local required_space_gb=${1:-5}  # Default 5GB minimum
    local available_space
    
    # Check available disk space (in GB)
    if command -v df >/dev/null 2>&1; then
        available_space=$(df -BG "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {gsub(/G/, "", $4); print $4}')
        if [[ -n "$available_space" ]] && [[ $available_space -lt $required_space_gb ]]; then
            echo "⚠️  WARNING: Low disk space: ${available_space}GB available, ${required_space_gb}GB recommended"
            return 1
        fi
    fi
    
    # Check memory usage
    if command -v vm_stat >/dev/null 2>&1; then
        local memory_pressure=$(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        if [[ -n "$memory_pressure" ]] && [[ $memory_pressure -lt 100000 ]]; then
            echo "⚠️  WARNING: Low memory available (Pages free: $memory_pressure)"
        fi
    fi
    
    return 0
}

# Log processing method and performance
log_processing_method() {
    local method="$1"
    local rotations="$2" 
    local duration="$3"
    local success="$4"
    local track_name="$5"
    
    local log_file="$OUTPUT_DIR/processing_log.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] TRACK: $track_name | METHOD: $method | ROTATIONS: $rotations | DURATION: ${duration}s | SUCCESS: $success" >> "$log_file"
    
    # Keep log file manageable (last 1000 entries)
    if [[ -f "$log_file" ]] && [[ $(wc -l < "$log_file") -gt 1000 ]]; then
        tail -1000 "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
    fi
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================
# Source this file in any script:
# source "$(dirname "$0")/../config/video_settings.sh"
# 
# Then use variables:
# rotation_speed=$(calculate_rotation_speed)
# cpu_cores=$(get_cpu_cores)
# total_rotations=$(calculate_rotations_needed "$duration") 