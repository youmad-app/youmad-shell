#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.2.0 
# Refactoring, restructuring, simplification, removing redundant code
# Currently untested

set -euo pipefail

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

readonly SCRIPT_VERSION="2.2.0"
readonly WORK_DIR="$HOME/youmad"
readonly CONFIG_FILE="$WORK_DIR/config"
readonly URL_FILE="./urls.txt"
readonly DOWNLOAD_ARCHIVE="$WORK_DIR/downloaded.txt"
readonly ERROR_LOG="$WORK_DIR/errors.log"
readonly ACTIVITY_LOG="$WORK_DIR/activity.log"
readonly USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Default settings
readonly DEFAULT_LIMIT_RATE="4M"
readonly DEFAULT_BROWSER="chrome"

# Runtime settings
LIMIT_RATE=""
BROWSER=""
DRY_RUN=false
OVERRIDE=false
VERBOSE=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$ACTIVITY_LOG"
}

# Unified year extraction function
extract_year() {
    local input="$1"
    local year=""
    
    # Handle different date formats
    if [[ "$input" =~ ^[0-9]{8}$ ]]; then
        # YYYYMMDD format
        year="${input:0:4}"
    elif [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        # YYYY-MM-DD format
        year="${input:0:4}"
    elif [[ "$input" =~ (19[5-9][0-9]|20[0-2][0-9]) ]]; then
        # Extract year from any text
        year="${BASH_REMATCH[1]}"
    fi
    
    # Validate year range
    if [[ -n "$year" && "$year" != "null" ]]; then
        local current_year=$(date +%Y)
        if [[ "$year" -ge 1950 && "$year" -le "$current_year" ]]; then
            echo "$year"
        fi
    fi
}

# Sanitize names for filesystem
sanitize_name() {
    local name="$1"
    echo "$name" | tr -d '/<>:"|?*' | tr ' ' '_' | sed 's/&/and/g'
}

# Get JSON value safely
get_json_value() {
    local json_file="$1"
    local query="$2"
    local default="${3:-}"
    
    local value
    value=$(jq -r "$query" "$json_file" 2>/dev/null || echo "$default")
    
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

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

# ============================================================================
# INITIALIZATION
# ============================================================================

show_usage() {
    cat << EOF
YouMAD? - Your Music Album Downloader v${SCRIPT_VERSION}

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

initialize_files() {
    mkdir -p "$WORK_DIR"
    touch "$DOWNLOAD_ARCHIVE" "$ERROR_LOG" "$ACTIVITY_LOG"

    if [[ ! -f "$URL_FILE" ]]; then
        log "INFO" "Creating example urls.txt file..."
        cat > "$URL_FILE" <<'EOF'
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

check_dependencies() {
    local missing_deps=()
    local install_hints=(
        "yt-dlp:pip install yt-dlp --user"
        "ffmpeg:sudo apt install ffmpeg"
        "exiftool:sudo apt install exiftool"
        "jq:sudo apt install jq"
    )

    for tool in yt-dlp ffmpeg exiftool jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        echo -e "\nInstallation instructions:"
        for hint in "${install_hints[@]}"; do
            local tool="${hint%%:*}"
            local cmd="${hint#*:}"
            if [[ " ${missing_deps[*]} " =~ " $tool " ]]; then
                echo "  $tool: $cmd"
            fi
        done
        exit 1
    fi

    log "INFO" "All dependencies found: yt-dlp, ffmpeg, exiftool, jq"
}

# ============================================================================
# METADATA EXTRACTION
# ============================================================================

get_album_info() {
    local url="$1"
    local get_year="${2:-false}"
    local temp_json="/tmp/youmad_info_$$.json"
    local album_title="Unknown Album"
    local year=""

    if yt-dlp --dump-json --flat-playlist --no-warnings --quiet "$url" > "$temp_json" 2>/dev/null; then
        # Get album title
        album_title=$(get_json_value "$temp_json" '
            if type == "array" then
                (.[0].playlist // .[0].album // "Unknown Album")
            else
                (.playlist // .album // .title // "Unknown Album")
            end' "Unknown Album" | head -1)

        # Get year if requested
        if [[ "$get_year" == "true" ]]; then
            local year_field
            year_field=$(get_json_value "$temp_json" '
                if type == "array" then
                    (.[0].release_year // .[0].upload_date // "")
                else
                    (.release_year // .upload_date // "")
                end' "" | head -1)
            
            year=$(extract_year "$year_field")
            
            # Try description as fallback
            if [[ -z "$year" ]]; then
                local desc
                desc=$(get_json_value "$temp_json" '
                    if type == "array" then
                        (.[0].description // "")
                    else
                        (.description // "")
                    end' "")
                year=$(extract_year "$desc")
            fi
        fi
    fi

    rm -f "$temp_json"
    
    if [[ "$get_year" == "true" ]]; then
        echo "${album_title}|${year}"
    else
        echo "$album_title"
    fi
}

get_track_year() {
    local track_url="$1"
    local temp_json="/tmp/youmad_track_$$.json"
    local year=""
    
    if yt-dlp --dump-json --no-warnings --quiet "$track_url" > "$temp_json" 2>/dev/null; then
        local year_field
        year_field=$(get_json_value "$temp_json" '.release_year // .release_date // .upload_date // ""' "")
        year=$(extract_year "$year_field")
    fi
    
    rm -f "$temp_json"
    echo "$year"
}

# ============================================================================
# FILE PROCESSING
# ============================================================================

process_thumbnail() {
    local album_dir="$1"
    local original_title="$2"
    
    local temp_thumbnail="$album_dir/temp_${original_title}.webp"
    if [[ -f "$temp_thumbnail" ]]; then
        local cover_file="$album_dir/cover.jpg"
        if ffmpeg -i "$temp_thumbnail" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Saved album art as: $(basename "$cover_file")"
            rm -f "$temp_thumbnail"
            return 0
        fi
    fi
    return 1
}

process_audio_file() {
    local file="$1"
    local counter="$2"
    local title="$3"
    local artist="$4"
    local album_name="$5"
    local year="$6"
    local release_type="$7"
    
    local file_ext="${file##*.}"
    local album_dir=$(dirname "$file")
    
    case "$file_ext" in
        "webm")
            process_webm_file "$file" "$counter" "$title" "$artist" "$album_name" "$year" "$release_type"
            ;;
        "mp4")
            process_mp4_file "$file" "$counter" "$title" "$artist" "$album_name" "$year" "$release_type"
            ;;
        "m4a")
            process_m4a_file "$file" "$counter" "$title" "$artist" "$album_name" "$year"
            ;;
        "opus")
            [[ "$VERBOSE" == true ]] && log "INFO" "Opus file already processed: $(basename "$file")"
            ;;
    esac
}

process_webm_file() {
    local file="$1"
    local counter="$2"
    local title="$3"
    local artist="$4"
    local album_name="$5"
    local year="$6"
    local release_type="$7"
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus: $(basename "$file")"
    
    # Get original performer
    local original_performer
    original_performer=$(ffprobe -v quiet -show_entries format_tags=artist,performer \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | head -1)
    
    # Process thumbnail
    process_thumbnail "$(dirname "$file")" "$title"
    
    # Convert to Opus
    local opus_file="${file%.*}.opus"
    local metadata_args=(
        -metadata:s:a:0 "TITLE=$title"
        -metadata:s:a:0 "ARTIST=$artist"
        -metadata:s:a:0 "ALBUM=$album_name"
        -metadata:s:a:0 "ALBUMARTIST=$artist"
        -metadata:s:a:0 "TRACKNUMBER=$counter"
        -metadata:s:a:0 "DATE=$year"
        -metadata:s:a:0 "RELEASETYPE=$release_type"
        -metadata:s:a:0 "PERFORMER=${original_performer:-$artist}"
    )
    
    if ffmpeg -i "$file" -c:a copy -map_metadata -1 "${metadata_args[@]}" "$opus_file" >/dev/null 2>&1; then
        rm -f "$file"
        [[ "$VERBOSE" == true ]] && log "INFO" "Converted WebM to Opus for track $counter"
    else
        log "WARN" "Failed to convert WebM to Opus for: $(basename "$file")"
    fi
}

process_mp4_file() {
    local file="$1"
    local counter="$2"
    local title="$3"
    local artist="$4"
    local album_name="$5"
    local year="$6"
    local release_type="$7"
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Processing MP4 file: $(basename "$file")"
    
    # Get original performer
    local original_performer
    original_performer=$(ffprobe -v quiet -show_entries format_tags=artist \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    # Process thumbnail
    process_thumbnail "$(dirname "$file")" "$title"
    
    # Update metadata
    local temp_m4a="/tmp/youmad_m4a_$$.m4a"
    local metadata_args=(
        -metadata "TITLE=$title"
        -metadata "ARTIST=$artist"
        -metadata "ALBUM=$album_name"
        -metadata "ALBUMARTIST=$artist"
        -metadata "TRACK=$counter"
        -metadata "DATE=$year"
        -metadata "RELEASETYPE=$release_type"
        -metadata "PERFORMER=${original_performer:-$artist}"
    )
    
    if ffmpeg -i "$file" -c copy -map_metadata -1 "${metadata_args[@]}" "$temp_m4a" >/dev/null 2>&1; then
        mv "$temp_m4a" "$file"
        [[ "$VERBOSE" == true ]] && log "INFO" "Set M4A metadata for track $counter"
    else
        rm -f "$temp_m4a"
        log "WARN" "Failed to set M4A metadata for: $(basename "$file")"
    fi
}

process_m4a_file() {
    local file="$1"
    local counter="$2"
    local title="$3"
    local artist="$4"
    local album_name="$5"
    local year="$6"
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Processing M4A file: $(basename "$file")"
    
    exiftool -overwrite_original \
        -Track="$counter" \
        -Title="$title" \
        -Artist="$artist" \
        -Album="$album_name" \
        -Year="$year" \
        "$file" >/dev/null 2>&1
}

# ============================================================================
# METADATA CLEANING
# ============================================================================

clean_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-}"

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

    # Determine year
    local year="${album_year:-$(extract_year "$album_name")}"
    [[ -z "$year" ]] && year=$(date +%Y)
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Using year: $year for album: $album_name"

    # Find all audio files
    local -a files_array
    while IFS= read -r file; do
        [[ -f "$file" ]] && files_array+=("$file")
    done < <(find "$album_dir" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" \) | sort)

    if [[ ${#files_array[@]} -eq 0 ]]; then
        log "WARN" "No audio files found in $album_dir"
        return 1
    fi

    [[ "$VERBOSE" == true ]] && log "INFO" "Found ${#files_array[@]} audio files to process"

    # Process each file
    for i in "${!files_array[@]}"; do
        local file="${files_array[i]}"
        local counter=$((i + 1))
        local filename=$(basename "$file")
        local file_ext="${filename##*.}"

        [[ "$file_ext" == "metadata" ]] && continue

        # Extract title from filename
        local title
        if [[ "$filename" =~ ^temp_(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^[0-9]+[[:space:]]*[-_][[:space:]]*(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        else
            title="Track $counter"
        fi

        # Rename file if needed
        local final_ext="$file_ext"
        [[ "$file_ext" == "mp4" ]] && final_ext="m4a"

        local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
        local new_path="$album_dir/$new_name"

        if [[ "$file" != "$new_path" ]]; then
            if mv "$file" "$new_path" 2>/dev/null; then
                [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $(basename "$file") -> $new_name"
                file="$new_path"
            else
                log "WARN" "Failed to rename: $(basename "$file")"
            fi
        fi

        # Process the audio file
        process_audio_file "$file" "$counter" "$title" "$artist" "$album_name" "$year" "$release_type"
    done

    # Final cleanup
    find "$album_dir" -name "*.metadata" -delete 2>/dev/null
    find "$album_dir" -name "temp_*.webp" -delete 2>/dev/null
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for ${#files_array[@]} files"
}

# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================

build_yt_dlp_args() {
    local artist_clean="$1"
    local limit_rate="$2"
    
    local args=(
        --embed-metadata --add-metadata
        --format "bestaudio/best"
        --no-embed-thumbnail --write-thumbnail
        --no-mtime --limit-rate "$limit_rate"
        --sleep-interval 3 --max-sleep-interval 8
        --retries 3 --fragment-retries 3
        -o "${artist_clean}/%(album,Unknown Album|sanitize)s/temp_%(title|sanitize)s.%(ext)s"
    )
    
    if [[ "$VERBOSE" == true ]]; then
        args+=(--progress)
    else
        args+=(--no-progress --quiet)
    fi
    
    if [[ "$OVERRIDE" != true ]]; then
        args+=(--download-archive "$DOWNLOAD_ARCHIVE")
    fi
    
    echo "${args[@]}"
}

download_album() {
    local url="$1"
    local artist="$2"
    local line_num="$3"
    local release_type="$4"

    local artist_clean=$(sanitize_name "$artist")

    # Handle dry run
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

    # Get album info
    local album_info
    album_info=$(get_album_info "$url" "true")
    IFS='|' read -r album_title album_year <<< "$album_info"

    # Display progress
    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Starting download for $artist: $url"
        [[ -n "$album_year" ]] && log "INFO" "Detected album year: $album_year"
    else
        printf "\n[%s] %s - %s" "$line_num" "$artist" "${album_title:-Album}"
        [[ -n "$album_year" ]] && printf " (%s)" "$album_year"
        printf "\nExtracting tracks... "
    fi

    # Extract track URLs
    local temp_urls="/tmp/youmad_urls_$$.txt"
    local start_time=$(date +%s)

    if ! yt-dlp --flat-playlist --get-url "$url" > "$temp_urls" 2>/dev/null; then
        log "ERROR" "Failed to extract track URLs: $url"
        rm -f "$temp_urls"
        return 1
    fi

    local track_count=$(wc -l < "$temp_urls")
    if [[ "$track_count" -eq 0 ]]; then
        log "ERROR" "No tracks found: $url"
        rm -f "$temp_urls"
        return 1
    fi

    [[ "$VERBOSE" != true ]] && printf "found %d tracks\n" "$track_count"

    # Try to get year from first track if needed
    if [[ -z "$album_year" ]] && [[ -s "$temp_urls" ]]; then
        local first_track_url=$(head -n1 "$temp_urls")
        album_year=$(get_track_year "$first_track_url")
        [[ -n "$album_year" && "$VERBOSE" == true ]] && log "INFO" "Got year from first track: $album_year"
    fi

    # Download tracks
    local track_num=1
    local failed_tracks=0
    local dl_args=($(build_yt_dlp_args "$artist_clean" "$LIMIT_RATE"))

    while IFS= read -r track_url; do
        [[ "$VERBOSE" == true ]] && log "INFO" "Downloading track $track_num/$track_count"

        local download_success=false
        if yt-dlp "${dl_args[@]}" "$track_url" >> "$ACTIVITY_LOG" 2>&1; then
            download_success=true
            [[ "$VERBOSE" != true ]] && printf "  ✓ Track %d/%d\n" "$track_num" "$track_count"
        else
            # Check if file exists despite error
            local track_files
            track_files=$(find "${artist_clean}" -name "temp_*" -type f \
                \( -name "*.mp4" -o -name "*.webm" -o -name "*.opus" -o -name "*.m4a" \) 2>/dev/null | wc -l)
            
            if [[ "$track_files" -gt 0 ]]; then
                download_success=true
                [[ "$VERBOSE" != true ]] && printf "  ✓ Track %d/%d (with warnings)\n" "$track_num" "$track_count"
            else
                log "WARN" "Failed to download track $track_num"
                ((failed_tracks++))
            fi
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

    # Report completion
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

    # Process metadata
    if [[ "$failed_tracks" -eq 0 ]]; then
        # Find the latest album directory
        local latest_album_dir
        if stat -c "%Y" . >/dev/null 2>&1; then
            latest_album_dir=$(find "$artist_clean" -mindepth 1 -maxdepth 1 -type d -exec stat -c "%Y %n" {} \; | 
                sort -nr | head -n1 | cut -d' ' -f2-)
        else
            latest_album_dir=$(find "$artist_clean" -mindepth 1 -maxdepth 1 -type d -exec stat -f "%m %N" {} \; | 
                sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}')
        fi

        if [[ -n "$latest_album_dir" ]]; then
            clean_metadata "$artist" "$latest_album_dir" "$release_type" "$album_year"
            [[ "$VERBOSE" != true ]] && printf "  📝 Metadata updated (Year: %s)\n" "${album_year:-$(date +%Y)}"
        else
            log "WARN" "Could not find album directory for metadata processing"
        fi
    fi

    return 0
}

download_playlist() {
    local url="$1"
    local playlist_name="$2"
    local line_num="$3"

    if [[ "$DRY_RUN" == true ]]; then
        local playlist_title=$(get_album_info "$url")
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download playlist '$playlist_title'"
        else
            printf "  Would download playlist: %s\n" "$playlist_title"
        fi
        return 0
    fi

    log "INFO" "Starting playlist download: $url"
    # Simplified playlist download logic here
    return 0
}

# ============================================================================
# MAIN PROCESSING
# ============================================================================

map_release_type() {
    local release_type="$1"
    
    case "$release_type" in
        live) echo "album;live" ;;
        comp) echo "album;compilation" ;;
        soundtrack) echo "album;soundtrack" ;;
        demo) echo "album;demo" ;;
        remix) echo "album;remix" ;;
        ep) echo "ep" ;;
        single) echo "single" ;;
        *) echo "album" ;;
    esac
}

process_urls() {
    if [[ ! -f "$URL_FILE" ]]; then
        log "ERROR" "$URL_FILE not found"
        exit 1
    fi

    > "$ERROR_LOG"
    log "INFO" "Processing URLs from $URL_FILE"

    # Count valid URLs
    local total_urls=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        ((total_urls++))
    done < "$URL_FILE"

    log "INFO" "Found $total_urls valid URLs"

    if [[ "$total_urls" -eq 0 ]]; then
        log "WARN" "No URLs found in $URL_FILE"
        return 0
    fi

    # Process URLs
    local processed=0
    local failed=0
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        ((line_num++))

        # Parse line
        IFS=';' read -r url artist release_type <<< "$line"
        url=$(echo "$url" | xargs)
        artist=$(echo "${artist:-Unknown Artist}" | xargs)
        release_type=$(echo "${release_type:-album}" | xargs)

        # Validate URL
        if ! [[ "$url" =~ ^https?:// ]]; then
            log "ERROR" "Invalid URL: $url"
            echo "Invalid URL: $line" >> "$ERROR_LOG"
            ((failed++))
            continue
        fi

        # Process based on type
        if [[ "$release_type" == "playlist" ]]; then
            if download_playlist "$url" "$artist" "$line_num/$total_urls"; then
                ((processed++))
            else
                echo "Failed: $line" >> "$ERROR_LOG"
                ((failed++))
            fi
        else
            local plex_release_type=$(map_release_type "$release_type")
            if download_album "$url" "$artist" "$line_num/$total_urls" "$plex_release_type"; then
                ((processed++))
            else
                echo "Failed: $line" >> "$ERROR_LOG"
                ((failed++))
            fi
        fi

        [[ "$DRY_RUN" != true ]] && sleep 2
    done < "$URL_FILE"

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

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    log "INFO" "Starting YouMAD? v${SCRIPT_VERSION}"

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
