#!/bin/bash
# set -x # Deactivated debugging

# YOYAKU Video Pipeline - Main Controller
# Version: 3.0 (Smart Auto-SKU & Destination-Driven UI)

set -e # Exit immediately if a command exits with a non-zero status.

# --- Global-like variables ---
SKU="" # Will be set by auto-detection

# --- Configuration & Setup ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
SCRIPTS_DIR="$SRC_DIR/scripts"
PYTHON_DIR="$SRC_DIR/python"
DATA_DIR="$PROJECT_ROOT/data"
INPUT_DIR="$DATA_DIR/input"
OUTPUT_DIR="$DATA_DIR/output"
CONFIG_DIR="$SRC_DIR/config"

# --- Logging ---
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local type="$1"
    local message="$2"
    local color
    case "$type" in
        INFO) color="$BLUE" ;;
        SUCCESS) color="$GREEN" ;;
        ERROR) color="$RED" ;;
        WARN) color="$YELLOW" ;;
        *) color="$NC" ;;
    esac
    printf "${color}[%s] %s - %s${NC}\n" "$type" "$(date +'%Y-%m-%d %H:%M:%S')" "$message"
}

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log "ERROR" "'jq' is not installed, but it's required for API interactions."
        log "INFO" "Please install it (e.g., 'brew install jq' on macOS) and try again."
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
🎬 YOYAKU YOUTUBE AUTOMATION PIPELINE
Connected to YouTube API for automated uploads

USAGE:
    ./run.sh [command] [mode]

COMMANDS:
    help      Show this help message
    setup     Setup the Python environment and YouTube API dependencies
    process   Process videos and upload to YouTube (default)
    clean     Clean temporary files and cache

VIDEO MODES (for process command):
    standard  Standard static video with YouTube upload (1280x720)
    spin      Spinning effect for Instagram Stories (1080x1350) - Local only
    spin169   Spinning effect with YouTube upload (1920x1080) + Full pipeline  
    enhanced  🎨 Enhanced visuals with gradients & advanced effects (1920x1080)
    smart     🎨 Smart visuals with color extraction & dynamic effects (1920x1080)
    simple    Simple static video for quick tests (1080x1350) - Local only
    basic     Basic merge of image and audio - Local only

EXAMPLES:
    ./run.sh                    # Process with standard mode (default)
    ./run.sh process            # Same as above
    ./run.sh process standard   # Standard YouTube pipeline (1280x720)
    ./run.sh process spin169    # Spinning effect + YouTube upload (1920x1080)
    ./run.sh process enhanced   # 🎨 Enhanced visuals with gradients + YouTube
    ./run.sh process smart      # 🎨 Smart visuals with color extraction + YouTube
    ./run.sh process spin       # Spinning effect for Instagram (local only)
    ./run.sh process simple     # Simple processing (local only)
    ./run.sh process basic      # Basic merge (local only)
    ./run.sh setup              # First-time YouTube API setup
    ./run.sh clean              # Clean up

PROJECT STRUCTURE:
    src/
    ├── scripts/          Shell scripts
    │   ├── mp4_yt.sh    🎯 Main YouTube pipeline (standard)
    │   ├── spin.sh      🌀 Spinning effect (Instagram local)
    │   ├── spin_16_9.sh 📺 Spinning effect + YouTube (16:9)
    │   ├── Simple.sh    ⚡ Simple processing (local)
    │   └── merge_*.sh   🔧 Basic merge (local)
    ├── python/           YouTube API scripts  
    └── config/           YouTube API credentials
    data/
    ├── input/            Audio files and images by SKU
    ├── output/           Generated videos
    └── temp/             Temporary files

YOUTUBE API FEATURES:
    ✅ Automated metadata scraping from yoyaku.io
    ✅ SEO-optimized descriptions and tags
    ✅ Automatic playlist creation by SKU
✅ Auto-opens YouTube Studio for monetization
    ✅ Retry logic for failed uploads
    ✅ Monetization-ready video settings

REQUIREMENTS:
    - Python 3.7+
    - FFmpeg
    - Active internet connection
    - YouTube API credentials (client_secret.json)

EOF
}

# Setup environment
setup_environment() {
    log "INFO" "Setting up environment..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log "ERROR" "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check FFmpeg
    if ! command -v ffmpeg &> /dev/null; then
        log "ERROR" "FFmpeg is required but not installed"
        exit 1
    fi
    
    # Install Python dependencies
    log "INFO" "Installing Python dependencies..."
    if [ -f "src/config/requirements.txt" ]; then
        pip3 install -r "src/config/requirements.txt"
    elif [ -f "requirements.txt" ]; then
        pip3 install -r "requirements.txt"
    else
        log "WARN" "requirements.txt not found, installing basic dependencies..."
        pip3 install google-api-python-client google-auth-httplib2 google-auth-oauthlib beautifulsoup4
    fi
    
    # Check config files
    if [[ ! -f "src/config/client_secret.json" ]] && [[ ! -f "client_secret.json" ]]; then
        log "WARN" "client_secret.json not found"
        log "WARN" "Please add your YouTube API credentials to src/config/ or project root"
    fi
    
    log "SUCCESS" "Setup completed successfully!"
}

# Clean temporary files and cache
clean_environment() {
    log "INFO" "🧹 Cleaning temporary files and cache..."
    
    # Clean temporary directories
    if [ -d "data/temp" ]; then
        rm -rf data/temp/*
        log "INFO" "✅ Cleaned data/temp/"
    fi
    
    # Clean Python cache
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -type f -delete 2>/dev/null || true
    log "INFO" "✅ Cleaned Python cache"
    
    # Clean old log files (keep last 10)
    if [ -d "logs" ]; then
        find logs -name "*.log" -type f | head -n -10 | xargs rm -f 2>/dev/null || true
        log "INFO" "✅ Cleaned old log files"
    fi
    
    # Clean ffmpeg temporary files
    find . -name "*.tmp" -type f -delete 2>/dev/null || true
    find . -name "ffmpeg2pass*" -type f -delete 2>/dev/null || true
    
    log "SUCCESS" "✅ Cleanup completed successfully!"
}

# Process videos and upload to YouTube
process_videos() {
    local mode=${1:-standard}
    
    log "INFO" "🎬 Starting video processing (mode: $mode)"
    
    # Check if input directory exists
    if [ ! -d "data/input" ]; then
        log "ERROR" "Input directory 'data/input' not found!"
        exit 1
    fi
    
    # Create output directory
    mkdir -p data/output
    
    # Select the appropriate script based on mode
    local script_path=""
    case $mode in
        standard)
            script_path="src/scripts/mp4_yt.sh"
            log "INFO" "🎯 Using standard processing (mp4_yt.sh)"
            ;;
        spin)
            script_path="src/scripts/spin.sh"
            log "INFO" "🌀 Using spinning effect (spin.sh)"
            ;;
        spin169)
            script_path="src/scripts/spin_16_9.sh"
            log "INFO" "📺 Using spinning effect with YouTube upload (spin_16_9.sh)"
            log "INFO" "🎬 Features: 1920x1080 resolution + rotation effect + YouTube API integration"
            ;;
        enhanced)
            script_path="src/scripts/spin_16_9_enhanced.sh"
            log "INFO" "🎨 Using enhanced visuals with gradients (spin_16_9_enhanced.sh)"
            log "INFO" "✨ Features: 1920x1080 + advanced visual effects + gradients + typography"
            ;;
        smart)
            script_path="src/scripts/smart_visual_youtube.sh"
            log "INFO" "🎨 Using smart visuals with color extraction (smart_visual_youtube.sh)"
            log "INFO" "🧠 Features: 1920x1080 + color extraction + dynamic effects + adaptive visuals"
            ;;
        simple)
            script_path="src/scripts/Simple.sh"
            log "INFO" "⚡ Using simple processing (Simple.sh)"
            ;;
        basic)
            script_path="src/scripts/merge_image_audio_fixed.sh"
            log "INFO" "🔧 Using basic merge (merge_image_audio_fixed.sh)"
            ;;
        *)
            log "ERROR" "Unknown video mode: $mode"
            echo "Available modes: standard, spin, spin169, enhanced, smart, simple, basic"
            echo ""
            echo "YouTube upload modes:"
            echo "  standard - Static video (1280x720) + YouTube upload"
            echo "  spin169  - Spinning video (1920x1080) + YouTube upload"
            echo "  enhanced - 🎨 Enhanced visuals with gradients (1920x1080) + YouTube upload"
            echo "  smart    - 🎨 Smart visuals with color extraction (1920x1080) + YouTube upload"
            echo ""
            echo "Local-only modes:"
            echo "  spin     - Spinning video (1080x1350) for Instagram"
            echo "  simple   - Simple static video (1080x1350)"  
            echo "  basic    - Basic image+audio merge"
            exit 1
            ;;
    esac
    
    # Check if script exists
    if [ ! -f "$script_path" ]; then
        log "ERROR" "Script not found: $script_path"
        exit 1
    fi
    
    # Make script executable
    chmod +x "$script_path"
    
    # Run the selected script
    log "INFO" "🚀 Executing: $script_path"
    if ! "$script_path"; then
        log "ERROR" "Video processing failed!"
        exit 1
    fi
    
    log "SUCCESS" "✅ Video processing completed successfully!"
}

# --- Core Functions ---
process() {
    local mode=${1:-standard}
    local sku=${2:-}
    
    log "INFO" "🎬 Starting video processing (mode: $mode, SKU: $sku)"
    
    # Check if input directory exists
    if [ ! -d "data/input" ]; then
        log "ERROR" "Input directory 'data/input' not found!"
        exit 1
    fi
    
    # Create output directory
    mkdir -p data/output
    
    # Select the appropriate script based on mode
    local script_path=""
    case $mode in
        standard)
            script_path="src/scripts/mp4_yt.sh"
            log "INFO" "🎯 Using standard processing (mp4_yt.sh)"
            ;;
        spin)
            script_path="src/scripts/spin.sh"
            log "INFO" "🌀 Using spinning effect (spin.sh)"
            ;;
        spin169)
            script_path="src/scripts/spin_16_9.sh"
            log "INFO" "📺 Using spinning effect with YouTube upload (spin_16_9.sh)"
            log "INFO" "🎬 Features: 1920x1080 resolution + rotation effect + YouTube API integration"
            ;;
        enhanced)
            script_path="src/scripts/spin_16_9_enhanced.sh"
            log "INFO" "🎨 Using enhanced visuals with gradients (spin_16_9_enhanced.sh)"
            log "INFO" "✨ Features: 1920x1080 + advanced visual effects + gradients + typography"
            ;;
        smart)
            script_path="src/scripts/smart_visual_youtube.sh"
            log "INFO" "🎨 Using smart visuals with color extraction (smart_visual_youtube.sh)"
            log "INFO" "🧠 Features: 1920x1080 + color extraction + dynamic effects + adaptive visuals"
            ;;
        simple)
            script_path="src/scripts/Simple.sh"
            log "INFO" "⚡ Using simple processing (Simple.sh)"
            ;;
        basic)
            script_path="src/scripts/merge_image_audio_fixed.sh"
            log "INFO" "🔧 Using basic merge (merge_image_audio_fixed.sh)"
            ;;
        *)
            log "ERROR" "Unknown video mode: $mode"
            echo "Available modes: standard, spin, spin169, enhanced, smart, simple, basic"
            echo ""
            echo "YouTube upload modes:"
            echo "  standard - Static video (1280x720) + YouTube upload"
            echo "  spin169  - Spinning video (1920x1080) + YouTube upload"
            echo "  enhanced - 🎨 Enhanced visuals with gradients (1920x1080) + YouTube upload"
            echo "  smart    - 🎨 Smart visuals with color extraction (1920x1080) + YouTube upload"
            echo ""
            echo "Local-only modes:"
            echo "  spin     - Spinning video (1080x1350) for Instagram"
            echo "  simple   - Simple static video (1080x1350)"  
            echo "  basic    - Basic image+audio merge"
            exit 1
            ;;
    esac
    
    # Check if script exists
    if [ ! -f "$script_path" ]; then
        log "ERROR" "Script not found: $script_path"
        exit 1
    fi
    
    # Make script executable
    chmod +x "$script_path"
    
    # Run the selected script
    log "INFO" "🚀 Executing: $script_path for SKU $sku"
    
    # Source the script to make its functions available, then call the function
    # This is more robust than just executing the file.
    source "$script_path"
    if ! create_video_montage "$INPUT_DIR/$sku" "$sku"; then
        log "ERROR" "Video processing failed!"
        exit 1
    fi
    
    log "SUCCESS" "✅ Video processing completed successfully!"
}

upload() {
    local sku="$1"
    log "INFO" "Attempting to upload videos for SKU: $sku"

    if [ ! -d "$OUTPUT_DIR/$sku" ]; then
        log "ERROR" "Output directory for SKU '$sku' not found: $OUTPUT_DIR/$sku"
        exit 1
    fi

    local video_files=("$OUTPUT_DIR/$sku"/*.mp4)
    if [ ${#video_files[@]} -eq 0 ]; then
        log "WARN" "No video files found in $OUTPUT_DIR/$sku. Skipping upload."
        return 0
    fi

    log "INFO" "Found ${#video_files[@]} video files to upload."

    # Step 1: Create or find playlist for this SKU
    log "INFO" "Creating/finding playlist for SKU: $sku"
    local client_secret_path="$CONFIG_DIR/client_secret.json"
    local playlist_id=$(python3 "$PYTHON_DIR/upload_to_youtube.py" "$client_secret_path" create_playlist "$sku")
    
    if [ -z "$playlist_id" ]; then
        log "ERROR" "Failed to create/find playlist for SKU: $sku"
        exit 1
    fi
    
    log "SUCCESS" "✅ Playlist ready for SKU $sku (ID: $playlist_id)"

    # Step 2: Upload videos and add them to playlist
    local uploaded_video_ids=()
    for video_file in "${video_files[@]}"; do
        log "INFO" "Uploading: $video_file"
        
        # Extract clean title from filename (remove path and extension)
        local base_name=$(basename "$video_file")
        local clean_title="${base_name%.*}"
        
        # Call the Python upload script with correct parameters
        local video_id=$(python3 "$PYTHON_DIR/upload_to_youtube.py" "$client_secret_path" upload_video "$video_file" "$clean_title" "$sku")
        
        if [ -n "$video_id" ]; then
            log "SUCCESS" "✅ Uploaded: $video_file (ID: $video_id)"
            uploaded_video_ids+=("$video_id")
            
            # Add video to playlist
            if python3 "$PYTHON_DIR/upload_to_youtube.py" "$client_secret_path" add_to_playlist "$playlist_id" "$video_id"; then
                log "SUCCESS" "✅ Added to playlist: $video_id"
            else
                log "WARN" "⚠️ Failed to add to playlist: $video_id"
            fi
        else
            log "ERROR" "❌ Failed to upload: $video_file"
        fi
    done

    log "SUCCESS" "All videos for SKU $sku have been uploaded and added to playlist '$sku' (${#uploaded_video_ids[@]} videos)."
    
    # Open YouTube Studio for manual monetization
    log "INFO" "💰 Opening YouTube Studio for manual monetization activation..."
    open "https://studio.youtube.com/channel/UCtSYkZGP9nkvXPMQgjeEIow/videos/upload?filter=%5B%5D&sort=%7B%22columnType%22%3A%22date%22%2C%22sortOrder%22%3A%22DESCENDING%22%7D"
    log "INFO" "📋 Video IDs uploaded: ${uploaded_video_ids[*]}"
    log "INFO" "👆 Please activate monetization for these videos in the opened YouTube Studio tab."
}

add_video_tag_to_product() {
    local sku="$1"
    log "INFO" "Attempting to add 'video' tag to product with SKU: $sku on yydistribution.fr"

    local base_url="https://yydistribution.fr/wp-json/wc/v3"
    local ck="ck_885b895a00ad69db88f4aa75e00c8983c2c96dad"
    local cs="cs_c188512b5144b0cc883cab2266d57f640969d5d6"
    local tag_name="video"

    # --- Step 1: Find Product ID from SKU ---
    local product_data
    product_data=$(curl -s -u "$ck:$cs" "$base_url/products?sku=$sku")
    local product_id
    product_id=$(echo "$product_data" | jq -r '.[0].id // empty')

    if [ -z "$product_id" ]; then
        log "ERROR" "Could not find product with SKU '$sku' on yydistribution.fr."
        return 1
    fi
    log "INFO" "Found Product ID: $product_id for SKU: $sku"

    # --- Step 2: Find or Create the 'video' Tag ID ---
    local tag_id
    tag_id=$(curl -s -u "$ck:$cs" "$base_url/products/tags?search=$tag_name" | jq -r '.[0].id // empty')

    if [ -z "$tag_id" ]; then
        log "INFO" "Tag '$tag_name' not found, creating it..."
        tag_id=$(curl -s -X POST -u "$ck:$cs" -H "Content-Type: application/json" \
            -d "{\"name\":\"$tag_name\"}" \
            "$base_url/products/tags" | jq -r '.id')
        if [ -z "$tag_id" ]; then
            log "ERROR" "Failed to create the '$tag_name' tag."
            return 1
        fi
        log "SUCCESS" "Created new '$tag_name' tag with ID: $tag_id"
    else
        log "INFO" "Found '$tag_name' tag with ID: $tag_id"
    fi

    # --- Step 3: Securely Add Tag (Non-Destructive) ---
    local existing_tags_json
    existing_tags_json=$(echo "$product_data" | jq -r '.[0].tags // []')
    
    # Check if tag is already present
    if echo "$existing_tags_json" | jq -e ".[] | select(.id == $tag_id)" > /dev/null; then
        log "INFO" "Product already has the '$tag_name' tag. No update needed."
        return 0
    fi
    
    # Add new tag to the existing list
    local updated_tags_json
    updated_tags_json=$(echo "$existing_tags_json" | jq ". + [{\"id\": $tag_id}]")

    # Update the product with the new list of tags
    local response
    response=$(curl -s -X PUT -u "$ck:$cs" -H "Content-Type: application/json" \
        -d "{\"tags\": $updated_tags_json}" \
        "$base_url/products/$product_id")

    # Verify the update was successful
    local updated_product_id
    updated_product_id=$(echo "$response" | jq -r '.id // empty')

    if [ "$updated_product_id" == "$product_id" ]; then
        log "SUCCESS" "Successfully added '$tag_name' tag to product $product_id."
    else
        log "ERROR" "Failed to update product $product_id. API Response: $(echo "$response" | jq .)"
        return 1
    fi
}

check_yyd_release() {
    local sku_to_check="$1"
    local url="http://yydistribution.fr/release/$sku_to_check"
    log "INFO" "Checking for B2B release page: $url"
    
    if curl --output /dev/null --silent --head --fail "$url"; then
        log "SUCCESS" "B2B release page found."
        return 0 # Success
    else
        log "INFO" "No B2B release page found for this SKU. Skipping server upload option."
        return 1 # Failure
    fi
}

package_and_upload_to_do() {
    local sku="$1"
    local output_sku_dir="$OUTPUT_DIR/$sku"
    local zip_file_path="$output_sku_dir/$sku.zip"
    
    log "INFO" "Starting packaging and upload for SKU: $sku"

    # --- Step 1: Compress videos into a zip file ---
    log "INFO" "Compressing videos into: $zip_file_path"
    if ! zip -j "$zip_file_path" "$output_sku_dir"/*.mp4 >/dev/null 2>&1; then
        log "ERROR" "Failed to create zip file."
        return 1
    fi
    log "SUCCESS" "Zip file created successfully."

    # --- Step 2: Upload to Digital Ocean Spaces ---
    local s3_path="/mp4/"
    log "INFO" "Uploading $zip_file_path to Digital Ocean Spaces at path '$s3_path'"
    
    if ! aws s3 cp "$zip_file_path" "s3://yydistribution${s3_path}${sku}.zip" --acl public-read --endpoint-url https://ams3.digitaloceanspaces.com; then
        log "ERROR" "Upload to Digital Ocean failed."
        # Clean up the local zip file even if upload fails
        rm "$zip_file_path"
        return 1
    fi

    # --- Step 3: Clean up local zip file and tag product ---
    log "SUCCESS" "File uploaded to Digital Ocean Spaces."
    rm "$zip_file_path"
    log "INFO" "Local zip file removed."

    # --- Step 4: Add 'video' tag to the product ---
    add_video_tag_to_product "$sku"
}

# --- New Interactive Menu Functions (v3.0) ---

# This function is called after a style is selected.
# It finds the SKU, runs the processing, and then the final action.
run_processing_flow() {
    local style_name="$1"
    local friendly_name="$2"
    local destination="$3" # "youtube" or "instagram"

    log "INFO" "Starting job: Style='$friendly_name', Destination='$destination'"

    # --- Auto-detect SKU ---
    local sku_dirs=("$INPUT_DIR"/*/)
    if [ ${#sku_dirs[@]} -eq 0 ]; then
        log "ERROR" "No SKU directory found in '$INPUT_DIR'. Please add one."
        exit 1
    fi
    if [ ${#sku_dirs[@]} -gt 1 ]; then
        log "ERROR" "Multiple SKU directories found in '$INPUT_DIR'. Please keep only one at a time."
        exit 1
    fi
    
    SKU=$(basename "${sku_dirs[0]}") # Make SKU a global-like variable for this script run
    log "SUCCESS" "Automatically detected SKU: $SKU"
    
    # --- Process Videos (Corrected Logic) ---
    log "INFO" "🎬 Starting video processing (mode: $style_name, SKU: $SKU)"
    
    local script_path=""
    case "$style_name" in
        "standard") script_path="$SCRIPTS_DIR/mp4_yt.sh" ;;
        "spin") script_path="$SCRIPTS_DIR/spin.sh" ;;
        "spin169") script_path="$SCRIPTS_DIR/spin_16_9.sh" ;;
        "simple") script_path="$SCRIPTS_DIR/Simple.sh" ;;
        "basic") script_path="$SCRIPTS_DIR/merge_image_audio_fixed.sh" ;;
        *)
            log "ERROR" "Internal error: Unknown style '$style_name'"
            exit 1 ;;
    esac

    if [ ! -f "$script_path" ]; then
        log "ERROR" "Script not found: $script_path"
        exit 1
    fi
    
    chmod +x "$script_path"
    log "INFO" "🚀 Executing: $script_path for SKU $SKU"
    source "$script_path"
    if ! create_video_montage "$INPUT_DIR/$SKU" "$SKU"; then
        log "ERROR" "Video processing failed!"
        exit 1
    fi
    log "SUCCESS" "✅ Video processing completed successfully!"


    # --- Final Action (Upload or Finish) ---
    if [ "$destination" == "youtube" ]; then
        log "INFO" "Processing complete. Now starting automatic YouTube upload..."
        upload "$SKU"
    else
        # Instagram destination - Check for B2B automatic workflow
        if check_yyd_release "$SKU"; then
            echo
            log "SUCCESS" "B2B release detected on YYDistribution.fr - Starting automatic upload workflow..."
            log "INFO" "🚀 Packaging and uploading videos to Digital Ocean Spaces..."
            package_and_upload_to_do "$SKU"
        else
            log "SUCCESS" "Instagram videos are ready in '$OUTPUT_DIR/$SKU/'."
        fi
    fi
}

show_youtube_submenu() {
    echo
    echo "-----------------------------------------------------"
    echo "STEP 2: What visual style for YouTube?"
    echo "-----------------------------------------------------"
    PS3="👉 Your choice: "
    local friendly_names=(
        "Static Visual (Vinyl Label or Cover)"
        "Spinning Vinyl Label"
        "Back"
    )
    select friendly_name in "${friendly_names[@]}"; do
        case "$friendly_name" in
            "Static Visual (Vinyl Label or Cover)")
                run_processing_flow "standard" "$friendly_name" "youtube"
                break ;;
            "Spinning Vinyl Label")
                run_processing_flow "spin169" "$friendly_name" "youtube"
                break ;;
            "Back")
                show_main_menu
                break ;;
            *) log "ERROR" "Invalid choice. Please try again." ;;
        esac
    done
}

show_instagram_submenu() {
    echo
    echo "-----------------------------------------------------"
    echo "STEP 2: What visual style for Instagram?"
    echo "-----------------------------------------------------"
    PS3="👉 Your choice: "
    local friendly_names=(
        "Static Visual (Vinyl Label or Cover)"
        "Spinning Vinyl Label"
        "Back"
    )
    local style_to_run=""
    local friendly_name_chosen=""

    select friendly_name in "${friendly_names[@]}"; do
        friendly_name_chosen="$friendly_name"
        case "$friendly_name" in
            "Static Visual (Vinyl Label or Cover)")
                style_to_run="simple"
                break ;;
            "Spinning Vinyl Label")
                style_to_run="spin"
                break ;;
            "Back")
                show_main_menu
                return ;;
            *) log "ERROR" "Invalid choice. Please try again." ;;
        esac
    done

    # Run the common processing flow
    run_processing_flow "$style_to_run" "$friendly_name_chosen" "instagram"
}

show_main_menu() {
    clear
    log "INFO" "Welcome to the YOYAKU Video Creation Assistant."
    echo
    echo "-----------------------------------------------------"
    echo "STEP 1: Where will this video be published?"
    echo "-----------------------------------------------------"
    PS3="👉 Your choice: "
    select destination in "YouTube (16:9 Landscape)" "Instagram (Vertical)" "Quit"; do
        case $destination in
            "YouTube (16:9 Landscape)")
                show_youtube_submenu
                break ;;
            "Instagram (Vertical)")
                show_instagram_submenu
                break ;;
            "Quit")
                log "INFO" "Operation cancelled by user."
                exit 0 ;;
            *) log "ERROR" "Invalid choice. Please try again." ;;
        esac
    done
}

main() {
    local command=${1:-}
    shift || true
    case "$command" in
        youtube|instagram)
            local destination="$command"
            local style=${1:-}
            if [ -z "$style" ]; then
                log "ERROR" "A style must be provided (e.g., 'spin', 'simple')."
                exit 1
            fi
            
            # This is the new non-interactive, full-flow command
            log "INFO" "Running full non-interactive flow for destination: '$destination', style: '$style'"
            
            # Re-use the processing flow logic, but non-interactively
            run_processing_flow "$style" "$style" "$destination" # friendly_name is just style here
            ;;
        process)
            local mode=${1:-standard}
            local sku=${2:-}
            if [ -z "$sku" ]; then
                log "ERROR" "SKU must be provided for 'process' command."
                exit 1
            fi
            process "$mode" "$sku"
            ;;
        upload)
            local sku=${1:-}
            if [ -z "$sku" ]; then
                log "ERROR" "SKU must be provided for 'upload' command."
                exit 1
            fi
            upload "$sku"
            ;;
        help|--help|-h)
            echo "YOYAKU Video Pipeline"
            echo "Usage: ./run.sh [command] [options]"
            echo ""
            echo "Commands:"
            echo "  <no command>    Launch the interactive assistant."
            echo "  process <style> <SKU>   Create videos for a specific SKU with a given style."
            echo "  upload <SKU>            Upload already created videos for a specific SKU."
            echo "  help                  Show this help message."
            ;;
        *)
            log "ERROR" "Unknown command: $command. Launching interactive assistant."
            show_main_menu
            ;;
    esac
}

# --- Script Execution ---
if [ "$#" -eq 0 ]; then
    # Interactive mode if no arguments
    check_dependencies
    show_main_menu
else
    # Command mode for experts/scripts
    main "$@"
fi 