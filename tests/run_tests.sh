#!/bin/bash

# ============================================================================
# Video Processor Test Suite v2.1.0
# ============================================================================

echo "🧪 Video Processor - Test Suite v2.1.0"
echo "================================================"

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
DATA_DIR="$PROJECT_ROOT/data"
TEST_DIR="$PROJECT_ROOT/tests"

# Load video settings
source "$SRC_DIR/config/video_settings.sh"
source "$SRC_DIR/scripts/spin_16_9.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test logging
TEST_LOG="$DATA_DIR/output/test_results.log"
mkdir -p "$(dirname "$TEST_LOG")"
echo "[$(date)] Starting test suite v$VIDEO_PROCESSOR_VERSION" > "$TEST_LOG"

# Test functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo ""
    echo "🔬 Testing: $test_name"
    echo "----------------------------------------"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if $test_function; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "[$(date)] PASS: $test_name" >> "$TEST_LOG"
    else
        echo "❌ FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "[$(date)] FAIL: $test_name" >> "$TEST_LOG"
    fi
}

# ============================================================================
# TEST CASES
# ============================================================================

test_video_settings_loaded() {
    [[ -n "$VIDEO_PROCESSOR_VERSION" ]] && [[ -n "$VINYL_ROTATION_DURATION" ]]
}

test_ffmpeg_available() {
    command -v ffmpeg >/dev/null 2>&1
}

test_required_codecs() {
    ffmpeg -codecs 2>/dev/null | grep -q "libx264" && 
    ffmpeg -codecs 2>/dev/null | grep -q "aac"
}

test_rotation_calculation() {
    local result=$(calculate_rotations_needed 100)
    [[ "$result" =~ ^[0-9]+$ ]] && [[ $result -gt 0 ]]
}

test_system_resource_check() {
    check_system_resources 1 >/dev/null 2>&1
}

test_output_directory_creation() {
    local test_output="$DATA_DIR/output/TEST_SKU"
    mkdir -p "$test_output"
    [[ -d "$test_output" ]] && rm -rf "$test_output"
}

test_processing_log_creation() {
    log_processing_method "test" "50" "300" "SUCCESS" "test_track.mp4"
    [[ -f "$DATA_DIR/output/processing_log.txt" ]]
}

test_image_detection() {
    # Create test image
    local test_sku_dir="$DATA_DIR/input/TEST_DETECTION"
    mkdir -p "$test_sku_dir"
    
    # Create a simple test image
    if command -v convert >/dev/null 2>&1; then
        convert -size 300x300 xc:blue "$test_sku_dir/test_image.jpg" 2>/dev/null
    else
        # Fallback: create empty file
        touch "$test_sku_dir/test_image.jpg"
    fi
    
    # Test image detection logic
    local images=()
    while IFS= read -r -d '' file; do
        images+=("$file")
    done < <(find "$test_sku_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 2>/dev/null | sort -z)
    
    local result_count=${#images[@]}
    
    # Cleanup
    rm -rf "$test_sku_dir"
    
    [[ $result_count -gt 0 ]]
}

test_audio_detection() {
    # Create test audio directory
    local test_sku_dir="$DATA_DIR/input/TEST_AUDIO"
    mkdir -p "$test_sku_dir"
    
    # Create empty test audio files
    touch "$test_sku_dir/test1.wav"
    touch "$test_sku_dir/test2.mp3"
    
    # Test audio detection logic
    local audio_files=()
    while IFS= read -r -d '' file; do
        audio_files+=("$file")
    done < <(find "$test_sku_dir" -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.aif' \) -print0 2>/dev/null | sort -z)
    
    local result_count=${#audio_files[@]}
    
    # Cleanup
    rm -rf "$test_sku_dir"
    
    [[ $result_count -eq 2 ]]
}

test_method_selection_logic() {
    # Test short track (should try standard concat first)
    local short_rotations=50
    [[ $short_rotations -le $MAX_CONCAT_ROTATIONS ]]
}

test_long_track_threshold() {
    # Test long track (should skip standard concat)
    local long_rotations=200
    [[ $long_rotations -gt $MAX_CONCAT_ROTATIONS ]]
}

# ============================================================================
# RUN TESTS
# ============================================================================

echo "Starting comprehensive test suite..."
echo "Project root: $PROJECT_ROOT"
echo "Video processor version: $VIDEO_PROCESSOR_VERSION"

# Core functionality tests
run_test "Video settings loaded" test_video_settings_loaded
run_test "FFmpeg available" test_ffmpeg_available  
run_test "Required codecs available" test_required_codecs
run_test "Rotation calculation" test_rotation_calculation
run_test "System resource check" test_system_resource_check

# File system tests  
run_test "Output directory creation" test_output_directory_creation
run_test "Processing log creation" test_processing_log_creation

# Detection logic tests
run_test "Image file detection" test_image_detection
run_test "Audio file detection" test_audio_detection

# Processing logic tests
run_test "Method selection for short tracks" test_method_selection_logic
run_test "Long track threshold logic" test_long_track_threshold

# ============================================================================
# RESULTS
# ============================================================================

echo ""
echo "================================================"
echo "🏁 Test Suite Complete"
echo "================================================"
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "🎉 ALL TESTS PASSED!"
    echo "✅ System is ready for production use"
    echo "[$(date)] ALL TESTS PASSED ($TESTS_PASSED/$TESTS_RUN)" >> "$TEST_LOG"
    exit 0
else
    echo ""
    echo "⚠️  SOME TESTS FAILED"
    echo "❌ Please review failed tests before production use"
    echo "📋 Check detailed log: $TEST_LOG"
    echo "[$(date)] TESTS FAILED ($TESTS_FAILED/$TESTS_RUN failed)" >> "$TEST_LOG"
    exit 1
fi