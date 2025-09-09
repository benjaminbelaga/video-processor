# 🔧 Troubleshooting Guide

## Common Issues and Solutions

### 🚨 Processing Failures

#### "All processing methods failed"
**Symptoms**: All 3 fallback methods fail for a track
**Solutions**:
1. Check audio file integrity:
   ```bash
   ffprobe -v error "path/to/audio.wav"
   ```
2. Verify image file:
   ```bash
   file "path/to/image.jpg"
   ```
3. Check processing log:
   ```bash
   tail -20 data/output/processing_log.txt
   ```

#### "No suitable images found"
**Symptoms**: Script can't find images in SKU folder  
**Solutions**:
1. Verify image formats: `.jpg`, `.jpeg`, `.png` supported
2. Check file permissions: `chmod 644 *.jpg`
3. Verify folder structure:
   ```
   data/input/SKU123/
   ├── track.wav
   └── cover.jpg  ✅
   ```

### ⚠️ Resource Issues

#### "Low disk space warning"
**Symptoms**: Warning about insufficient disk space
**Solutions**:
1. Free up space: Delete old temp files
   ```bash
   find data/temp -name "temp_rotation_*" -delete
   ```
2. Check actual usage:
   ```bash
   df -h data/output/
   ```

#### "Low memory available"  
**Symptoms**: Memory pressure warnings
**Solutions**:
1. Close other applications
2. Process fewer SKUs simultaneously
3. Use smaller batch sizes

### 🎬 Video Quality Issues

#### "Video quality inconsistency"
**Explanation**: Different methods produce different quality levels:
- **Standard concat**: Perfect quality (codec copy)
- **Stream loop**: High quality (re-encoded)  
- **Direct generation**: High quality (re-encoded)

**Solutions**:
1. For consistent quality, force one method:
   ```bash
   # Edit video_settings.sh
   MAX_CONCAT_ROTATIONS=0  # Forces stream_loop for all
   ```

#### "Audio sync issues"
**Symptoms**: Audio and video duration don't match
**Solutions**:
1. Check audio file with:
   ```bash
   ffprobe -show_format "audio.wav" | grep duration
   ```
2. Verify FFmpeg installation supports your audio format

### 🔄 FFmpeg Issues

#### "FFmpeg command not found"
**Solutions**:
1. Install FFmpeg:
   ```bash
   # macOS
   brew install ffmpeg
   
   # Ubuntu/Debian
   sudo apt install ffmpeg
   ```
2. Verify installation:
   ```bash
   ffmpeg -version
   ```

#### "Codec not supported"
**Symptoms**: Error about missing libx264 or aac
**Solutions**:
1. Install full FFmpeg build:
   ```bash
   brew install ffmpeg --with-libx264 --with-libfdk-aac
   ```

### 📊 Log Analysis

#### Understanding Processing Logs
```
[2025-09-09 16:33:14] TRACK: song.mp4 | METHOD: stream_loop | ROTATIONS: 102 | DURATION: 507s | SUCCESS: SUCCESS
```

**Fields**:
- **Timestamp**: When processing occurred
- **Track**: Filename being processed  
- **Method**: Which processing method was used
- **Rotations**: Number of rotation copies needed
- **Duration**: Audio track length in seconds
- **Success**: SUCCESS/FAILED status

#### Common Error Patterns
1. **"METHOD: STARTING ... SUCCESS: PENDING"** with no follow-up
   - Process was interrupted
   - Check system resources

2. **"METHOD: standard_concat ... SUCCESS: FAILED"** followed by **"METHOD: stream_loop ... SUCCESS: SUCCESS"**  
   - Normal fallback behavior
   - No action needed

3. **All methods show FAILED**
   - Critical issue with audio/image files
   - Check file integrity

### 🛠️ Advanced Debugging

#### Enable Verbose Logging
```bash
# Edit spin_16_9.sh, remove >/dev/null 2>&1 from FFmpeg commands
ffmpeg -threads "$CPU_CORES" \
    -f concat -safe 0 -i "$concat_list" \
    -i "$audio_file" \
    -c:v copy \
    # ... rest of command (remove the >/dev/null part)
```

#### Test Individual Components
```bash
# Test rotation generation
ffmpeg -loop 1 -framerate 30 -i image.jpg -t 5 -y test_rotation.mp4

# Test concatenation  
echo "file 'test_rotation.mp4'" > test_concat.txt
ffmpeg -f concat -safe 0 -i test_concat.txt -y test_final.mp4

# Test audio addition
ffmpeg -i test_final.mp4 -i audio.wav -c:v copy -c:a aac -shortest -y final.mp4
```

#### Check System Compatibility
```bash
# Verify all required tools
command -v ffmpeg && echo "FFmpeg: OK" || echo "FFmpeg: MISSING"
command -v bc && echo "bc: OK" || echo "bc: MISSING" 
command -v convert && echo "ImageMagick: OK" || echo "ImageMagick: MISSING"
```

## Performance Optimization

### For Large Batches
1. **Process in chunks**: Don't process 100+ SKUs at once
2. **Monitor resources**: Watch disk space and memory
3. **Use SSD storage**: Significantly faster than HDD

### For Very Long Tracks (30+ minutes)
1. **Increase swap space**: For emergency direct generation
2. **Close other apps**: Free maximum memory
3. **Use high-performance preset**: 
   ```bash
   VIDEO_PRESET="medium"  # Instead of "ultrafast"
   ```

## Getting Help

1. **Check logs first**: `data/output/processing_log.txt`
2. **Enable verbose mode**: Remove `>/dev/null 2>&1` from commands
3. **Create minimal test case**: Single problematic track
4. **Report issue**: Include logs, system info, and file details

### Issue Report Template
```
**System**: macOS 14.0 / Ubuntu 22.04
**FFmpeg version**: 6.0
**Track duration**: 15:30
**Method that failed**: standard_concat
**Error message**: [paste from logs]
**Files**: [describe audio/image formats]
```