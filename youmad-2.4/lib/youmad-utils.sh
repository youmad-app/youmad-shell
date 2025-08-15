#!/bin/bash
# YouMAD? - Utilities Module v2.4
# Extracted utilities and helper functions

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$ACTIVITY_LOG"
}

# Rotate activity log if it gets too large
rotate_log() {
    if [[ -f "$ACTIVITY_LOG" ]]; then
        local line_count=$(wc -l < "$ACTIVITY_LOG" 2>/dev/null || echo 0)
        
        if [[ "$line_count" -gt "$MAX_LOG_LINES" ]]; then
            log "INFO" "Activity log has $line_count lines, rotating..."
            
            # Rotate existing logs
            for ((i=$ROTATION_KEEP; i>=1; i--)); do
                local old_log="${ACTIVITY_LOG}.$i"
                local new_log="${ACTIVITY_LOG}.$((i+1))"
                [[ -f "$old_log" ]] && mv "$old_log" "$new_log" 2>/dev/null
            done
            
            # Keep the most recent portion of the current log
            local temp_log="/tmp/youmad_log_$.tmp"
            tail -n $((MAX_LOG_LINES / 2)) "$ACTIVITY_LOG" > "$temp_log"
            mv "$ACTIVITY_LOG" "${ACTIVITY_LOG}.1"
            mv "$temp_log" "$ACTIVITY_LOG"
            
            # Clean up old rotated logs beyond the keep limit
            for ((i=$((ROTATION_KEEP+2)); i<=10; i++)); do
                [[ -f "${ACTIVITY_LOG}.$i" ]] && rm -f "${ACTIVITY_LOG}.$i"
            done
            
            log "INFO" "Log rotated. Kept most recent $((MAX_LOG_LINES / 2)) lines"
        fi
    fi
}

# Cross-platform file modification time
get_file_mtime() {
    local file="$1"
    if stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat (Linux/WSL)
        stat -c "%Y" "$file" 2>/dev/null
    else
        # BSD stat (macOS)
        stat -f "%m" "$file" 2>/dev/null
    fi
}

# Cross-platform file sorting by modification time
sort_files_by_time() {
    local directory="$1"
    local pattern="$2"
    local temp_order="/tmp/youmad_order_$$.txt"
    
    if stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat (Linux/WSL)
        find "$directory" -name "$pattern" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" \) -exec stat -c "%Y %n" {} \; | sort -n | cut -d' ' -f2- > "$temp_order"
    else
        # BSD stat (macOS)
        find "$directory" -name "$pattern" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" \) -exec stat -f "%m %N" {} \; | sort -n | awk '{$1=""; sub(/^ /, ""); print}' > "$temp_order"
    fi
    
    echo "$temp_order"
}

# Create standardized temp file
create_temp_file() {
    local prefix="$1"
    local suffix="${2:-txt}"
    local temp_file="/tmp/youmad_${prefix}_$$.${suffix}"
    touch "$temp_file"
    echo "$temp_file"
}

# Cleanup temp files for this session
cleanup_temp_files() {
    rm -f "/tmp/youmad_*_$$"*
}

# Parse a single line from urls.txt (improved version)
parse_url_line() {
    local line="$1"
    local url=""
    local artist=""
    local release_type=""
    
    # Find the first semicolon
    if [[ "$line" == *";"* ]]; then
        url="${line%%;*}"
        local remainder="${line#*;}"
        
        # Find the second semicolon
        if [[ "$remainder" == *";"* ]]; then
            artist="${remainder%%;*}"
            release_type="${remainder#*;}"
        else
            artist="$remainder"
            release_type=""
        fi
    else
        url="$line"
        artist=""
        release_type=""
    fi
    
    # Trim whitespace using a simpler method
    url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    artist=$(echo "$artist" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    release_type=$(echo "$release_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Set defaults
    [[ -z "$artist" ]] && artist="Unknown Artist"
    [[ -z "$release_type" ]] && release_type="album"
    
    # Return the parsed values
    echo "$url|$artist|$release_type"
}

# Validate URL format
validate_url() {
    local url="$1"
    if echo "$url" | grep -q "^https\?://"; then
        return 0
    else
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    for tool in yt-dlp ffmpeg exiftool jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Installation instructions:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "yt-dlp") echo "  yt-dlp: pip install yt-dlp --user" ;;
                "ffmpeg") echo "  ffmpeg: sudo apt install ffmpeg" ;;
                "exiftool") echo "  exiftool: sudo apt install exiftool" ;;
                "jq") echo "  jq: sudo apt install jq" ;;
            esac
        done
        echo ""
        return 1
    fi

    log "INFO" "All dependencies found: yt-dlp, ffmpeg, exiftool, jq"
    return 0
}

# Show usage
show_usage() {
    cat << EOF
YouMAD? - Your Music Album Downloader v2.4

Usage: $0 [OPTIONS]

OPTIONS:
    --config         Create or recreate configuration interactively
    --show-config    Display current configuration
    --reset-config   Reset configuration to defaults
    --docker-init    Initialize Docker-friendly configuration
    --dry-run        Show what would be downloaded without downloading
    --override       Skip download archive check (re-download everything)
    --verbose        Enable verbose output
    --help           Show this help message

CONFIGURATION:
    Configuration is loaded from ~/.youmad/config and can be overridden
    with environment variables for Docker deployment:
    
    YOUMAD_LIMIT_RATE     - Download rate limit (e.g., 4M, 1M, 500K)
    YOUMAD_BROWSER        - Browser for cookies (chrome, firefox, etc.)
    YOUMAD_WORK_DIR       - Working directory (default: ~/youmad)
    YOUMAD_URL_FILE       - URL file location (default: ./urls.txt)
    YOUMAD_MAX_LOG_LINES  - Log rotation threshold (default: 5000)
    YOUMAD_ROTATION_KEEP  - Rotated logs to keep (default: 3)

REQUIREMENTS:
    - urls.txt file with format: URL;Artist Name;ReleaseType
    - yt-dlp, ffmpeg, exiftool, and jq installed

RELEASE TYPES:
    - album (default), ep, single, live, comp, soundtrack, demo, remix
    - playlist (simple download with format cleanup, no metadata processing)

The script downloads original files from YouTube Music and converts
WebM files to Opus without re-encoding. MP4 files are renamed to M4A
and cleaned up. M4A files are preserved as-is.

EXAMPLES:
    $0                    # Normal operation
    $0 --config          # Set up configuration
    $0 --verbose         # Show detailed progress
    $0 --dry-run         # Preview what would be downloaded
    
    # Docker deployment
    YOUMAD_LIMIT_RATE=2M $0  # Override download rate
    $0 --docker-init         # Initialize for container use
EOF
}

# Find latest album directory (cross-platform)
find_latest_album_dir() {
    local artist_dir="$1"
    [[ ! -d "$artist_dir" ]] && return 1

    if stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat (Linux/WSL)
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -c "%Y %n" {} \; | sort -nr | head -n1 | cut -d' ' -f2-
    else
        # BSD stat (macOS)
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -f "%m %N" {} \; | sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}'
    fi
}

# Initialize files
initialize_files() {
    # Rotate log if needed before starting
    rotate_log
    
    touch "$DOWNLOAD_ARCHIVE" "$ERROR_LOG" "$ACTIVITY_LOG"

    if [[ ! -f "$URL_FILE" ]]; then
        log "INFO" "Creating example urls.txt file..."
        cat > "$URL_FILE" <<EOF
# YouMAD? - URLs File
# Format: URL;Artist Name;ReleaseType
# Release types: album (default), ep, single, live, comp, soundtrack, demo, remix, playlist
#
# Examples:
# https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name
# https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;ep
# https://music.youtube.com/playlist?list=PLrAl6cWylHjwKpVROBfZyY5jzBCMjFhgs;Various;playlist

EOF
        log "INFO" "Created $URL_FILE with examples. Add your URLs and run again."
        exit 0
    fi
}
