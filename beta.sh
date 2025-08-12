#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.1.0

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

# Show usage
show_usage() {
    cat << EOF
YouMAD? - Your Music Album Downloader v2.1.0

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

PLAYLIST MODE:
    - Downloads entire playlist with original metadata preserved
    - Simple folder structure: Playlist/Track.ext
    - Converts WebM to Opus (container only, no re-encoding)
    - Renames MP4 to M4A
    - Preserves .opus and .m4a files as-is
    - Perfect for incremental playlist syncing

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

# Get album info
get_album_info() {
    local url="$1"
    local temp_json="/tmp/youmad_info_$$.json"

    if yt-dlp --dump-json --flat-playlist --no-warnings --quiet "$url" > "$temp_json" 2>/dev/null; then
        local album_title
        album_title=$(jq -r '
            if type == "array" then
                (.[0].playlist // .[0].album // "Unknown Album")
            else
                (.playlist // .album // .title // "Unknown Album")
            end' "$temp_json" 2>/dev/null | head -1)

        if [[ "$album_title" == "null" || -z "$album_title" ]]; then
            album_title="Unknown Album"
        fi

        rm -f "$temp_json"
        echo "$album_title"
    else
        rm -f "$temp_json"
        echo "Unknown Album"
        return 1
    fi
}

# Simple playlist file cleanup - converts WebM to Opus and MP4 to M4A, preserves all metadata
clean_playlist_files() {
    local playlist_dir="$1"

    if [[ "$DRY_RUN" == true ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "[DRY RUN] Would clean playlist files in $playlist_dir"
        return 0
    fi

    if [[ ! -d "$playlist_dir" ]]; then
        log "WARN" "Playlist directory not found: $playlist_dir"
        return 1
    fi

    [[ "$VERBOSE" == true ]] && log "INFO" "Cleaning playlist files in: $playlist_dir"

    # Process WebM files - convert container to Opus without re-encoding
    while IFS= read -r -d '' webm_file; do
        [[ ! -f "$webm_file" ]] && continue
        
        local opus_file="${webm_file%.*}.opus"
        [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus: $(basename "$webm_file")"
        
        if ffmpeg -i "$webm_file" -c copy "$opus_file" >/dev/null 2>&1; then
            rm -f "$webm_file"
            [[ "$VERBOSE" == true ]] && log "INFO" "Converted: $(basename "$webm_file") -> $(basename "$opus_file")"
        else
            log "WARN" "Failed to convert WebM to Opus: $(basename "$webm_file")"
        fi
    done < <(find "$playlist_dir" -name "*.webm" -type f -print0 2>/dev/null)

    # Process MP4 files - rename to M4A
    while IFS= read -r -d '' mp4_file; do
        [[ ! -f "$mp4_file" ]] && continue
        
        local m4a_file="${mp4_file%.*}.m4a"
        [[ "$VERBOSE" == true ]] && log "INFO" "Renaming MP4 to M4A: $(basename "$mp4_file")"
        
        if mv "$mp4_file" "$m4a_file" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $(basename "$mp4_file") -> $(basename "$m4a_file")"
        else
            log "WARN" "Failed to rename MP4 to M4A: $(basename "$mp4_file")"
        fi
    done < <(find "$playlist_dir" -name "*.mp4" -type f -print0 2>/dev/null)

    [[ "$VERBOSE" == true ]] && log "INFO" "Playlist file cleanup completed"
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

    # Get playlist info
    local playlist_title
    playlist_title=$(get_album_info "$url")

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Starting playlist download: $url"
    else
        printf "\n[%s] %s (playlist mode)\n" "$line_num" "${playlist_title:-Playlist}"
        printf "Downloading playlist... "
    fi

    local start_time=$(date +%s)

    # Download arguments for playlist
    local dl_args=(
        --embed-metadata --add-metadata
        --format "bestaudio/best"
        --no-write-thumbnail
        --no-write-playlist-metafiles
        --no-mtime --limit-rate "$LIMIT_RATE"
        --sleep-interval 3 --max-sleep-interval 8
        --retries 3 --fragment-retries 3
        -o "%(playlist,Unknown Playlist|sanitize)s/%(title|sanitize)s.%(ext)s"
    )

    if [[ "$VERBOSE" == true ]]; then
        dl_args+=(--progress)
    else
        dl_args+=(--no-progress --quiet)
    fi

    if [[ "$OVERRIDE" != true ]]; then
        dl_args+=(--download-archive "$DOWNLOAD_ARCHIVE")
    fi

    # Download playlist
    local download_success=false
    if [[ "$VERBOSE" == true ]]; then
        if yt-dlp "${dl_args[@]}" "$url" 2>&1 | tee -a "$ACTIVITY_LOG"; then
            download_success=true
        fi
    else
        if yt-dlp "${dl_args[@]}" "$url" >> "$ACTIVITY_LOG" 2>&1; then
            download_success=true
            printf "done\n"
        fi
    fi

    # Check if we actually got files, even if yt-dlp reported errors
    if [[ "$download_success" != true ]]; then
        # Look for any downloaded files to see if it actually succeeded despite errors
        local downloaded_files
        downloaded_files=$(find . -maxdepth 2 -name "*.mp4" -o -name "*.webm" -o -name "*.opus" -o -name "*.m4a" 2>/dev/null | wc -l)
        if [[ "$downloaded_files" -gt 0 ]]; then
            download_success=true
            printf "done (with warnings)\n"
        else
            printf "failed\n"
        fi
    fi

    if [[ "$download_success" != true ]]; then
        log "ERROR" "Failed to download playlist: $url"
        return 1
    fi

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Playlist download completed successfully"
    else
        printf "  ✅ Completed in %dm %ds\n" "$minutes" "$seconds"
    fi

    # Find and clean playlist files
    local playlist_dir
    if [[ -n "$playlist_title" && "$playlist_title" != "Unknown Album" ]]; then
        # Use the actual playlist title for directory name
        playlist_dir=$(echo "$playlist_title" | tr -d '/<>:"|?*' | tr ' ' '_')
        # Find directory that matches (yt-dlp sanitizes names)
        playlist_dir=$(find . -maxdepth 1 -type d -name "*$(echo "$playlist_title" | head -c 20)*" | head -n1)
    fi
    
    # Fallback: find the most recently created directory
    if [[ ! -d "$playlist_dir" ]]; then
        if stat -c "%Y" . >/dev/null 2>&1; then
            # GNU stat
            playlist_dir=$(find . -maxdepth 1 -type d ! -name "." -exec stat -c "%Y %n" {} \; | \
                sort -nr | head -n1 | cut -d' ' -f2-)
        else
            # BSD stat
            playlist_dir=$(find . -maxdepth 1 -type d ! -name "." -exec stat -f "%m %N" {} \; | \
                sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}')
        fi
    fi

    if [[ -n "$playlist_dir" && -d "$playlist_dir" ]]; then
        clean_playlist_files "$playlist_dir"
        [[ "$VERBOSE" != true ]] && printf "  📝 Files cleaned\n"
    else
        log "WARN" "Could not find playlist directory for cleanup"
    fi

    return 0
}

# Clean and set metadata (existing function for albums)
clean_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"

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

    # Try to extract year from album name, otherwise use a reasonable default
    local year="2020"  # Default year instead of current year
    if [[ "$album_name" =~ [[:space:]]([0-9]{4})[[:space:]]* ]]; then
        year="${BASH_REMATCH[1]}"
    elif [[ "$album_name" =~ ([0-9]{4}) ]]; then
        year="${BASH_REMATCH[1]}"
    fi

    # Sort files by creation time to preserve playlist order (audio files only, exclude metadata files)
    local temp_order="/tmp/youmad_order_$.txt"

    # Find all audio files (including mp4) and sort by creation time - FIXED to avoid duplicates
    find "$album_dir" -name "temp_*.*" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" -o -name "*.mp3" -o -name "*.aac" -o -name "*.flac" \) ! -name "*.metadata" > "$temp_order"

    # Fallback: if no temp_ files found, look for any audio files
    if [[ ! -s "$temp_order" ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "No temp_ files found, searching for any audio files"
        find "$album_dir" -name "*.*" -type f \( -name "*.webm" -o -name "*.opus" -o -name "*.m4a" -o -name "*.mp4" -o -name "*.mp3" -o -name "*.aac" -o -name "*.flac" \) ! -name "*.metadata" > "$temp_order"
    fi

    # Sort by creation time if possible, otherwise keep find order
    if stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat (Linux) - sort by creation time
        local temp_sorted="/tmp/youmad_sorted_$.txt"
        while IFS= read -r file; do
            [[ -f "$file" ]] && echo "$(stat -c "%Y" "$file" 2>/dev/null) $file"
        done < "$temp_order" | sort -n | cut -d' ' -f2- > "$temp_sorted"
        mv "$temp_sorted" "$temp_order"
    elif stat -f "%m" . >/dev/null 2>&1; then
        # BSD stat (macOS) - sort by creation time
        local temp_sorted="/tmp/youmad_sorted_$.txt"
        while IFS= read -r file; do
            [[ -f "$file" ]] && echo "$(stat -f "%m" "$file" 2>/dev/null) $file"
        done < "$temp_order" | sort -n | awk '{$1=""; sub(/^ /, ""); print}' > "$temp_sorted"
        mv "$temp_sorted" "$temp_order"
    fi

    # Debug: show what files we found
    if [[ "$VERBOSE" == true ]]; then
        local file_count=$(wc -l < "$temp_order" 2>/dev/null || echo "0")
        log "INFO" "Found $file_count audio files to process:"
        while IFS= read -r file; do
            [[ -f "$file" ]] && log "INFO" "  - $(basename "$file")"
        done < "$temp_order"
    fi

    # Process files in order
    local counter=1
    while IFS= read -r file; do
        [[ ! -f "$file" ]] && continue

        local filename=$(basename "$file")
        local file_ext="${filename##*.}"
        local current_file="$file"

        # Skip if this is a metadata file
        [[ "$file_ext" == "metadata" ]] && continue

        [[ "$VERBOSE" == true ]] && log "INFO" "Processing file $counter: $filename (type: $file_ext)"

        # Extract title from filename
        local title
        if [[ "$filename" =~ ^temp_(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^[0-9]+[[:space:]]*-[[:space:]]*(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^[^-]*-[[:space:]]*(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^(.*)\.[^.]+$ ]]; then
            title="${BASH_REMATCH[1]}"
        else
            title="Track $counter"
        fi

        # Store original title for thumbnail lookup (before renaming)
        local original_title="$title"

        # Determine final extension and rename file
        local final_ext="$file_ext"
        case "$file_ext" in
            "mp4")
                final_ext="m4a"  # Rename MP4 to M4A
                ;;
        esac

        local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
        local new_path="$album_dir/$new_name"

        if [[ "$current_file" != "$new_path" ]]; then
            if mv "$current_file" "$new_path" 2>/dev/null; then
                [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $(basename "$current_file") -> $new_name"
                current_file="$new_path"  # Update current_file to new path
            else
                log "WARN" "Failed to rename: $(basename "$current_file")"
            fi
        fi

        # Set metadata based on file type
        case "$file_ext" in
            "webm")
                # For WebM files, convert to Opus while preserving performer metadata
                [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus: $(basename "$current_file")"

                # Extract performer metadata from current WebM file
                local original_performer=""
                original_performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)

                if [[ -z "$original_performer" ]]; then
                    original_performer=$(ffprobe -v quiet -show_entries format_tags=performer -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
                fi

                # Create Opus filename and find corresponding thumbnail
                local opus_file="${current_file%.*}.opus"
                local thumbnail_file=""

                # Extract the original track title to find the matching thumbnail
                local track_title=""
                if [[ "$current_file" =~ ^.*/[0-9]+\ -\ (.*)\.webm$ ]]; then
                    track_title="${BASH_REMATCH[1]}"
                    # Look for the original temp thumbnail file using original title
                    local temp_thumbnail="$album_dir/temp_${original_title}.webp"
                    if [[ -f "$temp_thumbnail" ]]; then
                        thumbnail_file="$temp_thumbnail"
                    fi
                fi

                # Convert to Opus with comprehensive metadata cleaning
                local convert_cmd=(
                    ffmpeg -i "$current_file"
                    -c:a copy
                )

                # Note: Opus format doesn't support embedded album art, but we can save it as cover.jpg
                if [[ -n "$thumbnail_file" && -f "$thumbnail_file" ]]; then
                    local cover_file="$album_dir/cover.jpg"
                    # Convert WebP to square JPEG by cropping to center square
                    if ffmpeg -i "$thumbnail_file" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
                        [[ "$VERBOSE" == true ]] && log "INFO" "Saved square album art as: $(basename "$cover_file")"
                    else
                        [[ "$VERBOSE" == true ]] && log "WARN" "Failed to convert thumbnail to cover.jpg"
                    fi
                else
                    [[ "$VERBOSE" == true ]] && log "INFO" "No thumbnail found for: $title"
                fi

                # Strip ALL metadata first, then rebuild only what we want
                convert_cmd+=(
                    -map_metadata -1
                    -metadata:s:a:0 TITLE="$title"
                    -metadata:s:a:0 ARTIST="$artist"
                    -metadata:s:a:0 ALBUM="$album_name"
                    -metadata:s:a:0 ALBUMARTIST="$artist"
                    -metadata:s:a:0 TRACKNUMBER="$counter"
                    -metadata:s:a:0 DATE="$year"
                    -metadata:s:a:0 RELEASETYPE="$release_type"
                )

                # Add performer metadata
                if [[ -n "$original_performer" ]]; then
                    convert_cmd+=(-metadata:s:a:0 PERFORMER="$original_performer")
                    [[ "$VERBOSE" == true ]] && log "INFO" "Using original performer: $original_performer"
                else
                    convert_cmd+=(-metadata:s:a:0 PERFORMER="$artist")
                    [[ "$VERBOSE" == true ]] && log "INFO" "No original performer found, using artist: $artist"
                fi

                # Add the output file
                convert_cmd+=("$opus_file")

                if "${convert_cmd[@]}" >/dev/null 2>&1; then
                    rm -f "$current_file"
                    # Clean up the thumbnail file after we've processed it (but keep cover.jpg)
                    if [[ -n "$thumbnail_file" && -f "$thumbnail_file" ]]; then
                        rm -f "$thumbnail_file"
                    fi
                    [[ "$VERBOSE" == true ]] && log "INFO" "Converted WebM to Opus for track $counter"
                else
                    # Don't clean up thumbnails if conversion failed, for debugging
                    [[ "$VERBOSE" == true ]] && log "WARN" "Failed to convert WebM to Opus for: $(basename "$current_file") - keeping thumbnail for debugging"
                    log "WARN" "Failed to convert WebM to Opus for: $(basename "$current_file")"
                fi
                ;;
            "opus")
                # For existing Opus files, just update metadata
                local metadata_file="${album_dir}/temp_$(echo "$title" | tr ' ' '_').metadata"
                local original_performer=""

                # Try multiple metadata file patterns
                if [[ -f "$metadata_file" ]]; then
                    original_performer=$(cat "$metadata_file" 2>/dev/null)
                    rm -f "$metadata_file"  # Clean up the temp file
                    [[ "$VERBOSE" == true ]] && log "INFO" "Retrieved saved performer metadata: $original_performer"
                else
                    # Try with the original filename pattern
                    local orig_metadata_file="${file%.*}.metadata"
                    if [[ -f "$orig_metadata_file" ]]; then
                        original_performer=$(cat "$orig_metadata_file" 2>/dev/null)
                        rm -f "$orig_metadata_file"
                        [[ "$VERBOSE" == true ]] && log "INFO" "Retrieved saved performer metadata: $original_performer"
                    fi
                fi

                # If no saved metadata, try to extract from current file (use stream tags for Opus)
                if [[ -z "$original_performer" ]]; then
                    original_performer=$(ffprobe -v quiet -show_entries stream_tags=performer -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
                    if [[ -z "$original_performer" ]]; then
                        # Try artist field in stream tags
                        original_performer=$(ffprobe -v quiet -show_entries stream_tags=artist -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
                    fi
                fi

                local temp_opus="/tmp/youmad_meta_$.opus"

                # Build ffmpeg command with STREAM metadata for Opus
                local ffmpeg_cmd=(
                    ffmpeg -i "$current_file" -c copy
                    -map_metadata -1
                    -metadata:s:a:0 TITLE="$title"
                    -metadata:s:a:0 ARTIST="$artist"
                    -metadata:s:a:0 ALBUM="$album_name"
                    -metadata:s:a:0 ALBUMARTIST="$artist"
                    -metadata:s:a:0 TRACKNUMBER="$counter"
                    -metadata:s:a:0 DATE="$year"
                    -metadata:s:a:0 RELEASETYPE="$release_type"
                )

                # Add performer metadata
                if [[ -n "$original_performer" ]]; then
                    ffmpeg_cmd+=(-metadata:s:a:0 PERFORMER="$original_performer")
                    [[ "$VERBOSE" == true ]] && log "INFO" "Using original performer: $original_performer"
                else
                    ffmpeg_cmd+=(-metadata:s:a:0 PERFORMER="$artist")
                    [[ "$VERBOSE" == true ]] && log "INFO" "No original performer found, using artist: $artist"
                fi

                # Add output file
                ffmpeg_cmd+=("$temp_opus")

                if "${ffmpeg_cmd[@]}" >/dev/null 2>&1; then
                    mv "$temp_opus" "$current_file"
                    [[ "$VERBOSE" == true ]] && log "INFO" "Set Opus metadata for track $counter"
                else
                    rm -f "$temp_opus"
                    log "WARN" "Failed to set Opus metadata for: $(basename "$current_file")"
                fi
                ;;
            "mp4")
                # For MP4 files (now renamed to M4A), extract performer and set metadata
                [[ "$VERBOSE" == true ]] && log "INFO" "Processing MP4 (now M4A) file: $(basename "$current_file")"

                # Extract original performer from MP4 metadata
                local original_performer=""
                original_performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)

                if [[ -z "$original_performer" ]]; then
                    original_performer=$(ffprobe -v quiet -show_entries format_tags=performer -of default=noprint_wrappers=1:nokey=1 "$current_file" 2>/dev/null)
                fi

                # Find and process corresponding thumbnail file using original title
                local thumbnail_file="$album_dir/temp_${original_title}.webp"
                if [[ -f "$thumbnail_file" ]]; then
                    local cover_file="$album_dir/cover.jpg"
                    [[ "$VERBOSE" == true ]] && log "INFO" "Found thumbnail file: $(basename "$thumbnail_file")"
                    
                    # Convert WebP to square JPEG by cropping to center square
                    if ffmpeg -i "$thumbnail_file" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
                        [[ "$VERBOSE" == true ]] && log "INFO" "Saved square album art as: $(basename "$cover_file")"
                        # Clean up the thumbnail file after successful conversion
                        rm -f "$thumbnail_file"
                        [[ "$VERBOSE" == true ]] && log "INFO" "Cleaned up thumbnail: $(basename "$thumbnail_file")"
                    else
                        [[ "$VERBOSE" == true ]] && log "WARN" "Failed to convert thumbnail to cover.jpg, keeping original thumbnail"
                    fi
                else
                    [[ "$VERBOSE" == true ]] && log "INFO" "No thumbnail found for: $original_title (looked for: temp_${original_title}.webp)"
                fi

                # Build ffmpeg command to clean metadata (no thumbnail embedding)
                local temp_m4a="/tmp/youmad_m4a_$.m4a"
                local ffmpeg_cmd=(
                    ffmpeg -i "$current_file"
                    -c copy
                    -map_metadata -1
                    -metadata TITLE="$title"
                    -metadata ARTIST="$artist"
                    -metadata ALBUM="$album_name"
                    -metadata ALBUMARTIST="$artist"
                    -metadata TRACK="$counter"
                    -metadata DATE="$year"
                    -metadata RELEASETYPE="$release_type"
                )

                # Add performer metadata
                if [[ -n "$original_performer" ]]; then
                    ffmpeg_cmd+=(-metadata PERFORMER="$original_performer")
                    [[ "$VERBOSE" == true ]] && log "INFO" "Using original performer: $original_performer"
                else
                    ffmpeg_cmd+=(-metadata PERFORMER="$artist")
                    [[ "$VERBOSE" == true ]] && log "INFO" "No original performer found, using artist: $artist"
                fi

                # Add output file
                ffmpeg_cmd+=("$temp_m4a")

                if "${ffmpeg_cmd[@]}" >/dev/null 2>&1; then
                    if [[ -f "$temp_m4a" ]]; then
                        mv "$temp_m4a" "$current_file"
                        [[ "$VERBOSE" == true ]] && log "INFO" "Set M4A metadata for track $counter"
                    else
                        log "WARN" "ffmpeg succeeded but temp file not created: $temp_m4a"
                    fi
                else
                    rm -f "$temp_m4a"
                    log "WARN" "Failed to set M4A metadata for: $(basename "$current_file")"
                fi
                ;;
            "m4a")
                # For existing M4A files, just update metadata using exiftool
                exiftool -overwrite_original \
                    -Track="$counter" \
                    -TrackNumber="$counter" \
                    -Title="$title" \
                    -Artist="$artist" \
                    -Album="$album_name" \
                    -AlbumArtist="$artist" \
                    -Year="$year" \
                    -Date="$year" \
                    -RELEASETYPE="$release_type" \
                    -Description="" \
                    -LongDescription="" \
                    -Synopsis="" \
                    "$current_file" >/dev/null 2>&1
                [[ "$VERBOSE" == true ]] && log "INFO" "Set M4A metadata for track $counter"
                ;;
            *)
                log "WARN" "Unknown file type: $file_ext for file: $(basename "$current_file")"
                ;;
        esac

        ((counter++))

    done < "$temp_order"

    rm -f "$temp_order"

    # Clean up any remaining metadata files (but not thumbnails since they're cleaned individually)
    find "$album_dir" -name "*.metadata" -delete 2>/dev/null

    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for $((counter-1)) files"
}

# Find latest album directory
find_latest_album_dir() {
    local artist_dir="$1"
    [[ ! -d "$artist_dir" ]] && return 1

    if stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -c "%Y %n" {} \; | \
            sort -nr | head -n1 | cut -d' ' -f2-
    else
        # BSD stat
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -f "%m %N" {} \; | \
            sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}'
    fi
}

# Download album
download_album() {
    local url="$1"
    local artist="$2"
    local line_num="$3"
    local release_type="$4"

    # Sanitize artist name for filesystem
    local artist_clean="${artist//&/and}"
    artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')

    if [[ "$DRY_RUN" == true ]]; then
        local album_title
        album_title=$(get_album_info "$url")
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download '$album_title' by '$artist'"
        else
            printf "  Would download: %s - %s\n" "$artist" "$album_title"
        fi
        return 0
    fi

    # Get album info
    local album_title
    album_title=$(get_album_info "$url")

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Starting download for $artist: $url"
    else
        printf "\n[%s] %s - %s\n" "$line_num" "$artist" "${album_title:-Album}"
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

        # Check if files were actually downloaded, even if yt-dlp reported errors
        if [[ "$download_success" != true ]]; then
            # Look for downloaded files for this track
            local track_files
            track_files=$(find "${artist_clean}" -name "temp_*" -type f \( -name "*.mp4" -o -name "*.webm" -o -name "*.opus" -o -name "*.m4a" \) 2>/dev/null | wc -l)
            if [[ "$track_files" -gt 0 ]]; then
                download_success=true
                [[ "$VERBOSE" == true ]] && log "INFO" "Files found despite yt-dlp errors, treating as successful"
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

    # Report results
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

    # Process metadata only if download was successful
    if [[ "$failed_tracks" -eq 0 ]]; then
        local latest_album_dir
        latest_album_dir=$(find_latest_album_dir "$artist_clean")

        if [[ -n "$latest_album_dir" ]]; then
            clean_metadata "$artist" "$latest_album_dir" "$release_type"
            [[ "$VERBOSE" != true ]] && printf "  📝 Metadata updated\n"
        else
            log "WARN" "Could not find album directory for metadata processing"
        fi
    fi

    return 0
}

# Process all URLs
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
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        total_urls=$((total_urls + 1))
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
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        line_num=$((line_num + 1))

        # Parse line
        IFS=';' read -r url artist release_type <<< "$line"
        url="$(echo "$url" | xargs)"
        artist="$(echo "$artist" | xargs)"
        release_type="$(echo "$release_type" | xargs)"

        # Validate URL
        if ! echo "$url" | grep -q "^https\?://"; then
            log "ERROR" "Invalid URL: $url"
            echo "Invalid URL: $line" >> "$ERROR_LOG"
            failed=$((failed + 1))
            continue
        fi

        [[ -z "$artist" ]] && artist="Unknown Artist"

        # Check if this is playlist mode
        if [[ "$release_type" == "playlist" ]]; then
            # Use playlist download mode
            if download_playlist "$url" "$artist" "$line_num/$total_urls"; then
                processed=$((processed + 1))
            else
                echo "Failed: $line" >> "$ERROR_LOG"
                failed=$((failed + 1))
            fi
        else
            # Use album download mode with release type mapping
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

# Main function
main() {
    log "INFO" "Starting YouMAD? v2.1.0"

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
