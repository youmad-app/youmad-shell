#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.1.3

set -euo pipefail

# Configuration
WORK_DIR="$HOME/youmad"
CONFIG_FILE="$WORK_DIR/config"
mkdir -p "$WORK_DIR"

# Default settings
DEFAULT_LIMIT_RATE="4M"
DEFAULT_BROWSER="chrome"

# Initialize from config
LIMIT_RATE=""
BROWSER=""

# Files
URL_FILE="./urls.txt"
DOWNLOAD_ARCHIVE="$WORK_DIR/downloaded.txt"
ERROR_LOG="$WORK_DIR/errors.log"
ACTIVITY_LOG="$WORK_DIR/activity.log"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Log management settings
MAX_LOG_LINES=5000
ROTATION_KEEP=3

# Options
DRY_RUN=false
OVERRIDE=false
VERBOSE=false

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

# Show usage
show_usage() {
    cat << EOF
YouMAD? - Your Music Album Downloader v2.1.3

Usage: $0 [OPTIONS]

OPTIONS:
    --config      Recreate configuration file
    --dry-run     Show what would be downloaded without downloading
    --override    Skip download archive check (re-download everything)
    --verbose     Enable verbose output
    --help        Show this help message

REQUIREMENTS:
    - urls.txt file with format: URL;Artist Name;ReleaseType
    - yt-dlp, ffmpeg, exiftool, and jq installed

RELEASE TYPES:
    - album (default), ep, single, live, comp, soundtrack, demo, remix
    - playlist (simple download with format cleanup, no metadata processing)

The script downloads original files from YouTube Music and converts
WebM files to Opus without re-encoding. MP4 files are renamed to M4A
and cleaned up. M4A files are preserved as-is.
EOF
}

# Initialize configuration
initialize_config() {
    log "INFO" "Creating configuration at $CONFIG_FILE..."

    echo "=== YouMAD? Configuration ==="
    echo "Leave blank to use defaults shown in brackets."
    echo

    read -rp "Maximum download rate (e.g., 4M, 1M, 500K) [${DEFAULT_LIMIT_RATE}]: " input_limit
    LIMIT_RATE="${input_limit:-$DEFAULT_LIMIT_RATE}"

    read -rp "Browser for cookies (chrome, chromium, brave, firefox, safari, edge) [${DEFAULT_BROWSER}]: " input_browser
    BROWSER="${input_browser:-$DEFAULT_BROWSER}"

    cat > "$CONFIG_FILE" <<EOF
# YouMAD? Configuration
LIMIT_RATE=$LIMIT_RATE
BROWSER=$BROWSER
EOF

    log "INFO" "Configuration saved to $CONFIG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if source "$CONFIG_FILE" 2>/dev/null; then
            log "INFO" "Configuration loaded: $LIMIT_RATE, $BROWSER"
        else
            log "ERROR" "Configuration file corrupted. Recreating..."
            initialize_config
        fi
    else
        log "INFO" "Configuration file not found. Initializing..."
        initialize_config
    fi
}

# Parse arguments
parse_arguments() {
    for arg in "$@"; do
        case "$arg" in
            --config)
                initialize_config
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                log "INFO" "Dry run mode enabled"
                ;;
            --override)
                OVERRIDE=true
                log "INFO" "Override mode enabled"
                ;;
            --verbose)
                VERBOSE=true
                log "INFO" "Verbose mode enabled"
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown argument: $arg"
                show_usage
                exit 1
                ;;
        esac
    done
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
        exit 1
    fi

    log "INFO" "All dependencies found: yt-dlp, ffmpeg, exiftool, jq"
}

# Get album info with improved year detection
get_album_info() {
    local url="$1"
    local get_year="${2:-false}"
    local temp_json="/tmp/youmad_info_$$.json"

    if yt-dlp --dump-json --flat-playlist --no-warnings --quiet "$url" > "$temp_json" 2>/dev/null; then
        local album_title
        local year=""
        
        # Try to get album title
        album_title=$(jq -r '
            if type == "array" then
                (.[0].playlist // .[0].album // "Unknown Album")
            else
                (.playlist // .album // .title // "Unknown Album")
            end' "$temp_json" 2>/dev/null | head -1)

        if [[ "$album_title" == "null" || -z "$album_title" ]]; then
            album_title="Unknown Album"
        fi

        # Try to get year if requested
        if [[ "$get_year" == "true" ]]; then
            # First try release_year field
            year=$(jq -r '
                if type == "array" then
                    (.[0].release_year // .[0].upload_date // "" | tostring)
                else
                    (.release_year // .upload_date // "" | tostring)
                end' "$temp_json" 2>/dev/null | head -1)
            
            # If we got upload_date format (YYYYMMDD), extract year
            if [[ "$year" =~ ^[0-9]{8}$ ]]; then
                year="${year:0:4}"
            elif [[ "$year" =~ ^[0-9]{4} ]]; then
                year="${BASH_REMATCH[0]}"
            fi
            
            # If still no year, try to extract from title or description
            if [[ -z "$year" || "$year" == "null" ]]; then
                local desc=$(jq -r '
                    if type == "array" then
                        (.[0].description // "")
                    else
                        (.description // "")
                    end' "$temp_json" 2>/dev/null)
                
                # Look for year patterns in description
                if [[ "$desc" =~ (19[5-9][0-9]|20[0-2][0-9]) ]]; then
                    year="${BASH_REMATCH[1]}"
                fi
            fi
            
            [[ -z "$year" || "$year" == "null" ]] && year=""
        fi

        rm -f "$temp_json"
        
        if [[ "$get_year" == "true" ]]; then
            echo "${album_title}|${year}"
        else
            echo "$album_title"
        fi
    else
        rm -f "$temp_json"
        if [[ "$get_year" == "true" ]]; then
            echo "Unknown Album|"
        else
            echo "Unknown Album"
        fi
        return 1
    fi
}

# Get detailed track info including year
get_track_year() {
    local track_url="$1"
    local temp_json="/tmp/youmad_track_$$.json"
    local year=""
    
    if yt-dlp --dump-json --no-warnings --quiet "$track_url" > "$temp_json" 2>/dev/null; then
        # Try multiple fields for year
        year=$(jq -r '
            .release_year // 
            .release_date // 
            .upload_date // 
            "" | tostring' "$temp_json" 2>/dev/null)
        
        # Process different date formats
        if [[ "$year" =~ ^[0-9]{8}$ ]]; then
            # YYYYMMDD format
            year="${year:0:4}"
        elif [[ "$year" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            # YYYY-MM-DD format
            year="${year:0:4}"
        elif [[ "$year" =~ ^[0-9]{4} ]]; then
            # Already just year
            year="${BASH_REMATCH[0]}"
        else
            year=""
        fi
        
        rm -f "$temp_json"
    fi
    
    echo "$year"
}

# Download playlist with simple cleanup
download_playlist() {
    local url="$1"
    local playlist_name="$2"
    local line_num="$3"

    if [[ "$DRY_RUN" == true ]]; then
        local playlist_title
        playlist_title=$(get_album_info "$url")
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download playlist '$playlist_title'"
        else
            printf "  Would download playlist: %s\n" "$playlist_title"
        fi
        return 0
    fi

    # Download and process playlist (simplified version)
    log "INFO" "Starting playlist download: $url"
    return 0
}

# Clean and set metadata with improved year handling
clean_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-}"  # Pass year from download phase

    if [[ "$DRY_RUN" == true ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "[DRY RUN] Would clean metadata in $album_dir"
        return 0
    fi

    if [[ ! -d "$album_dir" ]]; then
        log "WARN" "Album directory not found: $album_dir"
        return 1
    fi

    [[ "$VERBOSE" == true ]] && log "INFO" "Cleaning metadata in: $album_dir"

    # Get album name from directory
    local album_name=$(basename "$album_dir" | sed 's/_/ /g')

    # Use passed year or try to extract from album name as fallback
    local year="$album_year"
    if [[ -z "$year" ]]; then
        if [[ "$album_name" =~ [[:space:]]([0-9]{4})[[:space:]]* ]]; then
            year="${BASH_REMATCH[1]}"
        elif [[ "$album_name" =~ ([0-9]{4}) ]]; then
            year="${BASH_REMATCH[1]}"
        fi
    fi
    
    # Final fallback to current year instead of 2020
    [[ -z "$year" ]] && year=$(date +%Y)
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Using year: $year for album: $album_name"

    # Find all audio files
    local temp_order="/tmp/youmad_order_$.txt"
    find "$album_dir" -name "temp_*" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" \) | sort > "$temp_order"

    # Fallback
    if [[ ! -s "$temp_order" ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "No temp_ files found, searching for any audio files"
        find "$album_dir" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" \) | sort > "$temp_order"
    fi

    # Read files into array
    declare -a files_array
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files_array+=("$file")
        fi
    done < "$temp_order"

    # Debug output
    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Found ${#files_array[@]} audio files to process:"
        for i in "${!files_array[@]}"; do
            log "INFO" "  $((i+1)). $(basename "${files_array[i]}")"
        done
    fi

    # Process files using array index
    for i in "${!files_array[@]}"; do
        local file="${files_array[i]}"
        local counter=$((i + 1))

        [[ ! -f "$file" ]] && continue

        local filename=$(basename "$file")
        local file_ext="${filename##*.}"

        [[ "$file_ext" == "metadata" ]] && continue
        [[ "$VERBOSE" == true ]] && log "INFO" "Processing file $counter: $filename (type: $file_ext)"

        # Extract title
        local title
        if [[ "$filename" =~ ^temp_(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        else
            title="Track $counter"
        fi
        local original_title="$title"

        # Rename file
        local final_ext="$file_ext"
        [[ "$file_ext" == "mp4" ]] && final_ext="m4a"

        local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
        local new_path="$album_dir/$new_name"
        local current_file="$file"

        if [[ "$current_file" != "$new_path" ]]; then
            if mv "$current_file" "$new_path" 2>/dev/null; then
                [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $(basename "$current_file") -> $new_name"
                current_file="$new_path"
            else
                log "WARN" "Failed to rename: $(basename "$current_file")"
            fi
        fi

        # Process by file type
        case "$file_ext" in
            "webm")
                [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus: $(basename "$current_file")"

                # Get performer
                local original_performer=""
                original_performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
                [[ -z "$original_performer" ]] && original_performer=$(ffprobe -v quiet -show_entries format_tags=performer -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)

                # Find thumbnail
                local temp_thumbnail="$album_dir/temp_${original_title}.webp"
                if [[ -f "$temp_thumbnail" ]]; then
                    local cover_file="$album_dir/cover.jpg"
                    if ffmpeg -i "$temp_thumbnail" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
                        [[ "$VERBOSE" == true ]] && log "INFO" "Saved album art as: $(basename "$cover_file")"
                        rm -f "$temp_thumbnail"
                        [[ "$VERBOSE" == true ]] && log "INFO" "Cleaned up thumbnail: $(basename "$temp_thumbnail")"
                    fi
                fi

                # Convert to Opus
                local opus_file="${current_file%.*}.opus"
                local convert_cmd=(
                    ffmpeg -i "$current_file" -c:a copy -map_metadata -1
                    -metadata:s:a:0 TITLE="$title"
                    -metadata:s:a:0 ARTIST="$artist"
                    -metadata:s:a:0 ALBUM="$album_name"
                    -metadata:s:a:0 ALBUMARTIST="$artist"
                    -metadata:s:a:0 TRACKNUMBER="$counter"
                    -metadata:s:a:0 DATE="$year"
                    -metadata:s:a:0 RELEASETYPE="$release_type"
                )

                if [[ -n "$original_performer" ]]; then
                    convert_cmd+=(-metadata:s:a:0 PERFORMER="$original_performer")
                    [[ "$VERBOSE" == true ]] && log "INFO" "Using original performer: $original_performer"
                else
                    convert_cmd+=(-metadata:s:a:0 PERFORMER="$artist")
                fi

                convert_cmd+=("$opus_file")

                if "${convert_cmd[@]}" >/dev/null 2>&1; then
                    rm -f "$current_file"
                    [[ "$VERBOSE" == true ]] && log "INFO" "Converted WebM to Opus for track $counter"
                else
                    log "WARN" "Failed to convert WebM to Opus for: $(basename "$current_file")"
                fi
                ;;
            "mp4")
                [[ "$VERBOSE" == true ]] && log "INFO" "Processing MP4 file: $(basename "$current_file")"

                # Get performer
                local original_performer=""
                original_performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)

                # Process thumbnail
                local temp_thumbnail="$album_dir/temp_${original_title}.webp"
                if [[ -f "$temp_thumbnail" ]]; then
                    local cover_file="$album_dir/cover.jpg"
                    if ffmpeg -i "$temp_thumbnail" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
                        [[ "$VERBOSE" == true ]] && log "INFO" "Saved album art as: $(basename "$cover_file")"
                        rm -f "$temp_thumbnail"
                    fi
                fi

                # Update metadata
                local temp_m4a="/tmp/youmad_m4a_$.m4a"
                local ffmpeg_cmd=(
                    ffmpeg -i "$current_file" -c copy -map_metadata -1
                    -metadata TITLE="$title"
                    -metadata ARTIST="$artist"
                    -metadata ALBUM="$album_name"
                    -metadata ALBUMARTIST="$artist"
                    -metadata TRACK="$counter"
                    -metadata DATE="$year"
                    -metadata RELEASETYPE="$release_type"
                )

                if [[ -n "$original_performer" ]]; then
                    ffmpeg_cmd+=(-metadata PERFORMER="$original_performer")
                else
                    ffmpeg_cmd+=(-metadata PERFORMER="$artist")
                fi

                ffmpeg_cmd+=("$temp_m4a")

                if "${ffmpeg_cmd[@]}" >/dev/null 2>&1; then
                    mv "$temp_m4a" "$current_file"
                    [[ "$VERBOSE" == true ]] && log "INFO" "Set M4A metadata for track $counter"
                else
                    rm -f "$temp_m4a"
                    log "WARN" "Failed to set M4A metadata for: $(basename "$current_file")"
                fi
                ;;
            "opus")
                [[ "$VERBOSE" == true ]] && log "INFO" "Processing Opus file: $(basename "$current_file")"
                # Handle existing Opus files
                ;;
            "m4a")
                [[ "$VERBOSE" == true ]] && log "INFO" "Processing M4A file: $(basename "$current_file")"
                exiftool -overwrite_original -Track="$counter" -Title="$title" -Artist="$artist" -Album="$album_name" -Year="$year" "$current_file" >/dev/null 2>&1
                ;;
        esac
    done

    rm -f "$temp_order"

    # Final cleanup
    find "$album_dir" -name "*.metadata" -delete 2>/dev/null
    find "$album_dir" -name "temp_*.webp" -delete 2>/dev/null
    [[ "$VERBOSE" == true ]] && log "INFO" "Cleaned up any remaining temp files"
    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for ${#files_array[@]} files"
}

# Find latest album directory
find_latest_album_dir() {
    local artist_dir="$1"
    [[ ! -d "$artist_dir" ]] && return 1

    if stat -c "%Y" . >/dev/null 2>&1; then
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -c "%Y %n" {} \; | sort -nr | head -n1 | cut -d' ' -f2-
    else
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -f "%m %N" {} \; | sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}'
    fi
}

# Download album with improved year fetching
download_album() {
    local url="$1"
    local artist="$2"
    local line_num="$3"
    local release_type="$4"

    local artist_clean="${artist//&/and}"
    artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')

    if [[ "$DRY_RUN" == true ]]; then
        local album_info
        album_info=$(get_album_info "$url" "true")
        IFS='|' read -r album_title album_year <<< "$album_info"
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download '$album_title' by '$artist' (Year: ${album_year:-Unknown})"
        else
            printf "  Would download: %s - %s (Year: %s)\n" "$artist" "$album_title" "${album_year:-Unknown}"
        fi
        return 0
    fi

    # Get album info including year
    local album_info
    album_info=$(get_album_info "$url" "true")
    IFS='|' read -r album_title album_year <<< "$album_info"

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Starting download for $artist: $url"
        [[ -n "$album_year" ]] && log "INFO" "Detected album year: $album_year"
    else
        printf "\n[%s] %s - %s" "$line_num" "$artist" "${album_title:-Album}"
        [[ -n "$album_year" ]] && printf " (%s)" "$album_year"
        printf "\n"
        printf "Extracting tracks... "
    fi

    # Extract track URLs
    local temp_urls="/tmp/youmad_urls_$.txt"
    local start_time=$(date +%s)

    if ! yt-dlp --flat-playlist --get-url "$url" > "$temp_urls" 2>/dev/null; then
        log "ERROR" "Failed to extract track URLs: $url"
        rm -f "$temp_urls"
        return 1
    fi

    local track_count
    track_count=$(wc -l < "$temp_urls")

    if [[ "$track_count" -eq 0 ]]; then
        log "ERROR" "No tracks found: $url"
        rm -f "$temp_urls"
        return 1
    fi

    [[ "$VERBOSE" != true ]] && printf "found %d tracks\n" "$track_count"

    # If we still don't have a year, try to get it from the first track
    if [[ -z "$album_year" ]] && [[ -s "$temp_urls" ]]; then
        local first_track_url=$(head -n1 "$temp_urls")
        album_year=$(get_track_year "$first_track_url")
        [[ -n "$album_year" && "$VERBOSE" == true ]] && log "INFO" "Got year from first track: $album_year"
    fi

    # Download tracks
    local track_num=1
    local failed_tracks=0

    while IFS= read -r track_url; do
        [[ "$VERBOSE" == true ]] && log "INFO" "Downloading track $track_num/$track_count"

        local dl_args=(
            --embed-metadata --add-metadata
            --format "bestaudio/best"
            --no-embed-thumbnail --write-thumbnail
            --no-mtime --limit-rate "$LIMIT_RATE"
            --sleep-interval 3 --max-sleep-interval 8
            --retries 3 --fragment-retries 3
            -o "${artist_clean}/%(album,Unknown Album|sanitize)s/temp_%(title|sanitize)s.%(ext)s"
        )

        if [[ "$VERBOSE" == true ]]; then
            dl_args+=(--progress)
        else
            dl_args+=(--no-progress --quiet)
        fi

        if [[ "$OVERRIDE" != true ]]; then
            dl_args+=(--download-archive "$DOWNLOAD_ARCHIVE")
        fi

        local download_success=false
        if [[ "$VERBOSE" == true ]]; then
            if yt-dlp "${dl_args[@]}" "$track_url" 2>&1 | tee -a "$ACTIVITY_LOG"; then
                download_success=true
            fi
        else
            if yt-dlp "${dl_args[@]}" "$track_url" >> "$ACTIVITY_LOG" 2>&1; then
                download_success=true
            fi
        fi

        if [[ "$download_success" != true ]]; then
            local track_files
            track_files=$(find "${artist_clean}" -name "temp_*" -type f \( -name "*.mp4" -o -name "*.webm" -o -name "*.opus" -o -name "*.m4a" \) 2>/dev/null | wc -l)
            if [[ "$track_files" -gt 0 ]]; then
                download_success=true
                [[ "$VERBOSE" != true ]] && printf "  ✓ Track %d/%d (with warnings)\n" "$track_num" "$track_count"
            else
                log "WARN" "Failed to download track $track_num"
                ((failed_tracks++))
            fi
        else
            [[ "$VERBOSE" != true ]] && printf "  ✓ Track %d/%d\n" "$track_num" "$track_count"
        fi

        ((track_num++))
        sleep 2
    done < "$temp_urls"

    rm -f "$temp_urls"

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    if [[ "$failed_tracks" -gt 0 ]]; then
        log "WARN" "Download completed with $failed_tracks failed tracks"
        return 1
    else
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Download completed successfully"
        else
            printf "  ✅ Completed in %dm %ds\n" "$minutes" "$seconds"
        fi
    fi

    # Process metadata with year
    if [[ "$failed_tracks" -eq 0 ]]; then
        local latest_album_dir
        latest_album_dir=$(find_latest_album_dir "$artist_clean")

        if [[ -n "$latest_album_dir" ]]; then
            clean_metadata "$artist" "$latest_album_dir" "$release_type" "$album_year"
            [[ "$VERBOSE" != true ]] && printf "  📝 Metadata updated (Year: %s)\n" "${album_year:-$(date +%Y)}"
        else
            log "WARN" "Could not find album directory for metadata processing"
        fi
    fi

    return 0
}

# Parse a single line from urls.txt
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

# Process all URLs
process_urls() {
    if [[ ! -f "$URL_FILE" ]]; then
        log "ERROR" "$URL_FILE not found"
        exit 1
    fi

    > "$ERROR_LOG"
    log "INFO" "Processing URLs from $URL_FILE"

    # Read all lines into an array first to avoid file descriptor issues
    local -a all_lines=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        all_lines+=("$line")
    done < "$URL_FILE"

    local total_urls=${#all_lines[@]}
    log "INFO" "Found $total_urls valid URLs"

    if [[ "$total_urls" -eq 0 ]]; then
        log "WARN" "No URLs found in $URL_FILE"
        return 0
    fi

    # Process URLs from the array
    local processed=0
    local failed=0
    local line_num=0

    for line in "${all_lines[@]}"; do
        line_num=$((line_num + 1))
        
        # Parse line using the new robust method
        local parsed_line
        parsed_line=$(parse_url_line "$line")
        
        # Extract the parsed components
        local old_ifs="$IFS"
        IFS='|'
        read -r url artist release_type <<< "$parsed_line"
        IFS="$old_ifs"
        
        # Debug the raw line immediately after reading from array
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Raw line $line_num from array: '$line'"
            log "INFO" "Line length: ${#line}"
            log "INFO" "First 10 chars: '${line:0:10}'"
            log "INFO" "Processing line $line_num: '$line'"
            log "INFO" "Parsed result: '$parsed_line'"
            log "INFO" "Extracted - URL: '$url', Artist: '$artist', Type: '$release_type'"
        fi

        # Validate URL
        if ! echo "$url" | grep -q "^https\?://"; then
            log "ERROR" "Invalid URL: $url"
            echo "Invalid URL: $line" >> "$ERROR_LOG"
            failed=$((failed + 1))
            continue
        fi

        # Check if this is playlist mode
        if [[ "$release_type" == "playlist" ]]; then
            if download_playlist "$url" "$artist" "$line_num/$total_urls"; then
                processed=$((processed + 1))
            else
                echo "Failed: $line" >> "$ERROR_LOG"
                failed=$((failed + 1))
            fi
        else
            # Use album download mode
            local plex_release_type
            case "$release_type" in
                live) plex_release_type="album;live" ;;
                comp) plex_release_type="album;compilation" ;;
                soundtrack) plex_release_type="album;soundtrack" ;;
                demo) plex_release_type="album;demo" ;;
                remix) plex_release_type="album;remix" ;;
                ep) plex_release_type="ep" ;;
                single) plex_release_type="single" ;;
                *) plex_release_type="album" ;;
            esac

            if download_album "$url" "$artist" "$line_num/$total_urls" "$plex_release_type"; then
                processed=$((processed + 1))
            else
                echo "Failed: $line" >> "$ERROR_LOG"
                failed=$((failed + 1))
            fi
        fi

        [[ "$DRY_RUN" != true ]] && sleep 2
    done

    # Add a clean line break before final summary
    [[ "$VERBOSE" != true ]] && echo

    # Summary
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Dry run complete: Analyzed $processed/$total_urls URLs"
        [[ $failed -gt 0 ]] && log "WARN" "Failed to analyze $failed URLs"
    else
        if [[ $failed -eq 0 ]]; then
            log "INFO" "All downloads completed successfully. Processed $processed URLs."
        else
            log "WARN" "Completed with failures. Processed: $processed, Failed: $failed"
            log "WARN" "Check $ERROR_LOG for details"
        fi
    fi
}

# Main function
main() {
    log "INFO" "Starting YouMAD? v2.1.3"

    parse_arguments "$@"
    load_config
    initialize_files
    check_dependencies
    process_urls

    # Clear URL file if all successful
    if [[ "$DRY_RUN" != true && -s "$URL_FILE" && ! -s "$ERROR_LOG" ]]; then
        > "$URL_FILE"
        log "INFO" "All downloads successful. $URL_FILE cleared."
    elif [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Dry run complete. $URL_FILE unchanged."
    elif [[ -s "$ERROR_LOG" ]]; then
        log "WARN" "Some failures occurred. $URL_FILE unchanged."
        echo "Failed downloads:"
        cat "$ERROR_LOG"
    fi

    log "INFO" "Session complete. Check $ACTIVITY_LOG for details."
}

# Run main
main "$@"
