#!/bin/bash

echo "Starting the spinning video montage script..."

# Getting the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
DATA_DIR="$PROJECT_ROOT/data"
CONFIG_DIR="$SRC_DIR/config"
PYTHON_DIR="$SRC_DIR/python"

TEMP_DIR="$DATA_DIR/input"
OUTPUT_DIR="$DATA_DIR/output"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Load centralized video settings (SINGLE SOURCE OF TRUTH)
source "$CONFIG_DIR/video_settings.sh"

# Get settings from SINGLE SOURCE OF TRUTH
CPU_CORES=$(get_cpu_cores)
PRESET="$VIDEO_PRESET"
RESOLUTION_W="$YOUTUBE_WIDTH"
RESOLUTION_H="$YOUTUBE_HEIGHT"
AUDIO_BITRATE="$AUDIO_BITRATE"
PIXEL_FORMAT="$PIXEL_FORMAT"

create_video_montage() {
    local sku_dir="$1"
    local sku="$2"

    echo "=== Processing SKU: $sku with Spinning Effect (v$VIDEO_PROCESSOR_VERSION) ==="
    echo "🔧 Build: $VIDEO_PROCESSOR_BUILD_DATE"
    
    # Check system resources before starting
    check_system_resources 3  # Require 3GB free space
    
    # Create a folder named after the SKU inside the output directory
    local sku_output_dir="$OUTPUT_DIR/$sku"
    mkdir -p "$sku_output_dir"

    # Find all images with names ending in "1400" first (higher quality)
    local images=()
    while IFS= read -r -d '' file; do
        images+=("$file")
    done < <(find "$sku_dir" -type f \( -iname '*1400.jpg' -o -iname '*1400.jpeg' -o -iname '*1400.png' \) -print0 | sort -z)
    
    local num_images=${#images[@]}

    # If no images ending with '1400', use all images in the folder
    if [[ $num_images -eq 0 ]]; then
        echo "No '1400' images found, using all images alphabetically."
        while IFS= read -r -d '' file; do
            images+=("$file")
        done < <(find "$sku_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 | sort -z)
        num_images=${#images[@]}
    fi

    if [[ $num_images -eq 0 ]]; then
        echo "No suitable images found in $sku_dir for SKU $sku. Skipping..."
        return
    fi

    echo "Found $num_images images in $sku_dir"

    # Convert PNG images to have a black background (only if they are PNGs)
    for image in "${images[@]}"; do
        if [[ "$image" == *.png ]]; then
            echo "Converting PNG to black background: $image"
            magick convert "$image" -background black -flatten "$image" 2>/dev/null || true
        fi
    done

    # Process each audio file (.mp3, .wav, and .aif)
    local audio_files=()
    while IFS= read -r -d '' file; do
        audio_files+=("$file")
    done < <(find "$sku_dir" -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.aif' \) -print0 | sort -z)
    
    local num_audio_files=${#audio_files[@]}
    
    # Check if there are any audio files to process
    if [[ $num_audio_files -eq 0 ]]; then
        echo "No .mp3, .wav, or .aif files found in $sku_dir for SKU $sku. Skipping..."
        return
    fi

    echo "Found $num_audio_files audio files in $sku_dir"

    local half_num_audio_files=$(( (num_audio_files + 1) / 2 ))

    # Process each audio file with spinning effect
    for i in "${!audio_files[@]}"; do
        local audio_file="${audio_files[$i]}"
        echo ""
        echo "--- Processing track $((i + 1))/$num_audio_files ---"
        echo "Audio file: $audio_file"
        
        local base_name=$(basename "$audio_file")
        local extension="${base_name##*.}"
        base_name="${base_name%.*}"
        
        # Standardized output path, using the raw audio filename.
        # The intelligent upload script will handle the final YouTube title.
        local output_video="$sku_output_dir/${base_name}.mp4"

        # Determine which image to use (alternate between images if multiple)
        local image_file="${images[0]}"
        if [[ $num_images -ge 2 && $i -ge $half_num_audio_files ]]; then
            image_file="${images[1]}"
        fi
        echo "Using image: $image_file"

        # Skip if video already exists
        if [[ -f "$output_video" ]]; then
            echo "Video already exists, skipping creation: $(basename "$output_video")"
            continue
        fi

        # Get the duration of the audio file with proper error handling
        local duration
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
        
        # Check if duration is valid
        if [[ -z "$duration" || "$duration" == "N/A" ]]; then
            echo "Warning: Could not get duration for $audio_file, skipping..."
            continue
        fi
        
        echo "Audio duration: $duration seconds"
        
        # Log the processing attempt
        log_processing_method "STARTING" "$total_rotations" "$duration" "PENDING" "$(basename "$output_video")"

        # Determine the scaling factor to fit the image within resolution while maintaining aspect ratio
        scale="${RESOLUTION_W}:${RESOLUTION_H}:force_original_aspect_ratio=decrease"
        pad="pad=${RESOLUTION_W}:${RESOLUTION_H}:(ow-iw)/2:(oh-ih)/2:color=black"

                # ULTRA-OPTIMIZED spinning: Pre-calculate sequence + concatenation
        echo "Creating ultra-fast vinyl spinning video: $(basename "$output_video")"
        
        # Step 1: Create one rotation sequence (1.8s at 33⅓ RPM)
        local temp_rotation="$sku_output_dir/temp_rotation_$(basename "$output_video")"
        # Use SINGLE SOURCE OF TRUTH for rotation settings
        local rotation_duration="$VINYL_ROTATION_DURATION"
        local rotation_speed=$(calculate_rotation_speed)
        local total_rotations=$(calculate_rotations_needed "$duration")
        
        echo "🔄 Step 1: Creating ultra-smooth base rotation (${rotation_duration}s, need ${total_rotations} copies)..."
        if ffmpeg -threads "$CPU_CORES" \
            -loop 1 -framerate "$VIDEO_FRAMERATE" -i "$image_file" \
            -c:v libx264 -preset "$PRESET" -tune stillimage \
            -pix_fmt "$PIXEL_FORMAT" \
            -vf "scale=$scale,$pad,rotate=$rotation_speed*t:bilinear=0:fillcolor=black" \
            -t "$rotation_duration" \
            -movflags +faststart \
            -y "$temp_rotation" >/dev/null 2>&1; then
            
            echo "✅ Base rotation created"
            
            # Step 2: Create concat list and final video
            local concat_list="$sku_output_dir/concat_list_$(basename "$output_video" .mp4).txt"
            echo "🔄 Step 2: Creating concat list for ${total_rotations} rotations..."
            
            # Generate concat list
            for ((i=1; i<=total_rotations; i++)); do
                echo "file '$temp_rotation'" >> "$concat_list"
            done
            
            echo "🔄 Step 3: Concatenating rotations and adding audio..."
            
            # SMART PROCESSING: Try methods in order of efficiency
            success=false
            method_used="unknown"
            
            # METHOD 1: Standard concat (fastest, best quality) - Try first for all tracks
            if [[ $total_rotations -le 150 ]]; then
                echo "📋 Attempting standard concatenation method (${total_rotations} rotations)..."
                if ffmpeg -threads "$CPU_CORES" \
                    -f concat -safe 0 -i "$concat_list" \
                    -i "$audio_file" \
                    -c:v copy \
                    -c:a aac -b:a "$AUDIO_BITRATE" \
                    -shortest \
                    -movflags +faststart \
                    -y "$output_video" 2>/tmp/ffmpeg_concat_error.log; then
                    success=true
                    method_used="standard_concat"
                    echo "✅ Success with standard concatenation"
                else
                    echo "⚠️  Standard concatenation failed, trying optimized method..."
                    cat /tmp/ffmpeg_concat_error.log | tail -3 | sed 's/^/    ERROR: /'
                fi
            fi
            
            # METHOD 2: Stream loop (memory efficient) - Fallback for long tracks or concat failures
            if [[ "$success" != "true" ]]; then
                echo "🔄 Using stream_loop method (${total_rotations} rotations)..."
                if ffmpeg -threads "$CPU_CORES" \
                    -stream_loop $((total_rotations - 1)) -i "$temp_rotation" \
                    -i "$audio_file" \
                    -c:v libx264 -preset "$PRESET" -pix_fmt "$PIXEL_FORMAT" \
                    -c:a aac -b:a "$AUDIO_BITRATE" \
                    -shortest \
                    -movflags +faststart \
                    -y "$output_video" 2>/tmp/ffmpeg_stream_error.log; then
                    success=true
                    method_used="stream_loop"
                    echo "✅ Success with stream_loop method"
                else
                    echo "⚠️  Stream loop failed, trying emergency method..."
                    cat /tmp/ffmpeg_stream_error.log | tail -3 | sed 's/^/    ERROR: /'
                fi
            fi
            
            # METHOD 3: Emergency direct generation (slowest but most reliable)
            if [[ "$success" != "true" ]]; then
                echo "🚨 EMERGENCY: Direct generation method (${total_rotations} rotations)..."
                # Calculate total duration and generate directly without pre-rotation
                if ffmpeg -threads "$CPU_CORES" \
                    -loop 1 -framerate "$VIDEO_FRAMERATE" -i "$image_file" \
                    -i "$audio_file" \
                    -c:v libx264 -preset "$PRESET" -tune stillimage \
                    -pix_fmt "$PIXEL_FORMAT" \
                    -vf "scale=$scale,$pad,rotate=$rotation_speed*t:bilinear=0:fillcolor=black" \
                    -c:a aac -b:a "$AUDIO_BITRATE" \
                    -shortest \
                    -movflags +faststart \
                    -y "$output_video" 2>/tmp/ffmpeg_direct_error.log; then
                    success=true
                    method_used="direct_generation"
                    echo "✅ Success with emergency direct generation"
                else
                    echo "❌ ALL METHODS FAILED for track: $(basename "$output_video")"
                    cat /tmp/ffmpeg_direct_error.log | tail -5 | sed 's/^/    FINAL ERROR: /'
                fi
            fi
            
            if [[ "$success" == "true" ]]; then
                echo "🎯 Method used: $method_used (${total_rotations} rotations)"
                
                # Log successful processing
                log_processing_method "$method_used" "$total_rotations" "$duration" "SUCCESS" "$(basename "$output_video")"
                 
                 # Clean up temporary files
                 rm -f "$temp_rotation" "$concat_list"
                 
                 # Verify the created file is valid
            if [[ -f "$output_video" ]] && ffprobe -v error "$output_video" >/dev/null 2>&1; then
                local file_size=$(stat -f%z "$output_video" 2>/dev/null || stat -c%s "$output_video" 2>/dev/null)
                echo "✅ Successfully created spinning video: $(basename "$output_video") (${file_size} bytes)"
                             else
                     echo "❌ Created file is corrupted: $(basename "$output_video")"
                     rm -f "$output_video"
                     continue
                 fi
             else
                 echo "❌ CRITICAL FAILURE: All processing methods failed for: $(basename "$output_video")"
                 echo "📊 Track stats: ${total_rotations} rotations, ${duration}s duration"
                 
                 # Log the failure
                 log_processing_method "ALL_METHODS_FAILED" "$total_rotations" "$duration" "FAILED" "$(basename "$output_video")"
                 
                 # Clean up and continue with next track
                 rm -f "$temp_rotation" "$concat_list" "$output_video"
                 
                 # Show recent processing log for debugging
                 if [[ -f "$OUTPUT_DIR/processing_log.txt" ]]; then
                     echo "📋 Recent processing log (last 5 entries):"
                     tail -5 "$OUTPUT_DIR/processing_log.txt" | sed 's/^/    /'
                 fi
                 
                 continue
             fi
         else
             echo "❌ Failed to create base rotation: $(basename "$output_video")"
             rm -f "$temp_rotation" "$concat_list"
             continue
         fi
    done
    
    echo ""
    echo "=== SKU $sku processing completed ==="
}

# This script is intended to be called by other scripts (like run.sh),
# not executed directly. The main processing logic is now in run.sh.
# Example of how to call this function:
# create_video_montage "/path/to/data/input/SKU123" "SKU123"
