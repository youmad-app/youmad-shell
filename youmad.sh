#!/bin/bash
# YouMAD? - Your Music Album Downloader v1.0.1

set -euo pipefail

# Default Configuration
WORK_DIR="$HOME/youmad"
CONFIG_FILE="$WORK_DIR/config"
mkdir -p "$WORK_DIR"

# Hardcoded Defaults
DEFAULT_FORMAT="m4a"
DEFAULT_LIMIT_RATE="4M"
DEFAULT_BROWSER="chrome"

# Initialize as empty; populated from config if valid
FORMAT=""
LIMIT_RATE=""
BROWSER=""

URL_FILE="./urls.txt"
DOWNLOAD_ARCHIVE="$WORK_DIR/downloaded.txt"
ERROR_LOG="$WORK_DIR/errors.log"
ACTIVITY_LOG="$WORK_DIR/activity.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

# Show usage information
show_usage() {
    cat << EOF
YouMAD? - Your Music Album Downloader v1.0.1

Usage: $0 [OPTIONS]

OPTIONS:
    --config      Recreate configuration file
    --dry-run     Show what would be downloaded without actually downloading
    --override    Skip download archive check (re-download everything)
    --verbose     Enable verbose output
    --help        Show this help message

REQUIREMENTS:
    - urls.txt file with URLs and artists (format: URL;Artist Name[;ReleaseType])
    - yt-dlp, ffmpeg, and exiftool installed

RELEASE TYPES:
    - album (default)
    - ep
    - single
    - live (album;live)
    - comp (album;compilation)
    - soundtrack (album;soundtrack)
    - demo (album;demo)
    - remix (album;remix)
EOF
}

# Initialize configuration
initialize_config() {
    log "INFO" "Creating YouMAD? configuration at $CONFIG_FILE..."

    echo "=== YouMAD? Configuration ==="
    echo "Leave blank to use defaults shown in brackets."
    echo

    read -rp "Preferred audio format (m4a, mp3, opus, flac, wav) [${DEFAULT_FORMAT}]: " input_format
    FORMAT="${input_format:-$DEFAULT_FORMAT}"

    read -rp "Maximum download rate (e.g., 4M, 1M, 500K) [${DEFAULT_LIMIT_RATE}]: " input_limit
    LIMIT_RATE="${input_limit:-$DEFAULT_LIMIT_RATE}"

    read -rp "Browser to extract cookies from (chrome, chromium, brave, firefox, safari, edge) [${DEFAULT_BROWSER}]: " input_browser
    BROWSER="${input_browser:-$DEFAULT_BROWSER}"

    cat > "$CONFIG_FILE" <<EOF
# YouMAD? Configuration
FORMAT=$FORMAT
LIMIT_RATE=$LIMIT_RATE
BROWSER=$BROWSER
EOF

    log "INFO" "YouMAD? configuration saved to $CONFIG_FILE"
}

# Validate or create configuration
validate_or_create_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        if source "$CONFIG_FILE" 2>/dev/null; then
            log "INFO" "YouMAD? configuration loaded: $FORMAT, $LIMIT_RATE, $BROWSER"
        else
            log "ERROR" "YouMAD? configuration file corrupted. Recreating..."
            initialize_config
        fi
    else
        log "INFO" "YouMAD? configuration file not found. Initializing..."
        initialize_config
    fi
}

# Parse command line arguments
parse_arguments() {
    for arg in "$@"; do
        case "$arg" in
            --config)
                initialize_config
                log "INFO" "YouMAD? configuration recreated. Exiting."
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                log "INFO" "YouMAD? dry run mode enabled."
                ;;
            --override)
                OVERRIDE=true
                log "INFO" "YouMAD? override mode enabled - will re-download existing files."
                ;;
            --verbose)
                VERBOSE=true
                log "INFO" "YouMAD? verbose mode enabled."
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

# Initialize required files
initialize_files() {
    touch "$DOWNLOAD_ARCHIVE" "$ERROR_LOG" "$ACTIVITY_LOG"

    if [[ ! -f "$URL_FILE" ]]; then
        log "INFO" "Creating example urls.txt file..."
        cat > "$URL_FILE" <<EOF
# YouMAD? - URLs File
# Format: URL;Artist Name[;ReleaseType]
# Release types: album (default), ep, single, live, comp, soundtrack, demo, remix
#
# Examples:
# https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name
# https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;ep
# https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;live

EOF
        log "INFO" "Created $URL_FILE with examples. Please add your URLs and run YouMAD? again."
        exit 0
    fi
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()

    # Check core dependencies
    for tool in yt-dlp ffmpeg jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done

    # Check format-specific dependencies
    if [[ "$FORMAT" == "opus" ]]; then
        # For opus format, we need opustags instead of exiftool
        if ! command -v "opustags" >/dev/null 2>&1; then
            missing_deps+=("opustags")
        fi
    else
        # For all other formats, we need exiftool
        if ! command -v "exiftool" >/dev/null 2>&1; then
            missing_deps+=("exiftool")
        fi
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "YouMAD? missing dependencies: ${missing_deps[*]}"
        
        # Provide helpful installation instructions
        echo ""
        echo "Installation instructions:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "opustags")
                    echo "  opustags: sudo apt install opustags  (or build from https://github.com/fmang/opustags)"
                    ;;
                "exiftool")
                    echo "  exiftool: sudo apt install exiftool  (Ubuntu/Debian)"
                    ;;
                "yt-dlp")
                    echo "  yt-dlp: pip install yt-dlp --user"
                    ;;
                "ffmpeg")
                    echo "  ffmpeg: sudo apt install ffmpeg  (Ubuntu/Debian)"
                    ;;
                "jq")
                    echo "  jq: sudo apt install jq  (Ubuntu/Debian)"
                    ;;
            esac
        done
        echo ""
        exit 1
    fi

    if [[ "$FORMAT" == "opus" ]]; then
        log "INFO" "YouMAD? dependencies found: yt-dlp, ffmpeg, opustags, jq"
    else
        log "INFO" "YouMAD? dependencies found: yt-dlp, ffmpeg, exiftool, jq"
    fi
}

# Cross-platform function to find latest directory
find_latest_album_dir() {
    local artist_dir="$1"

    if [[ ! -d "$artist_dir" ]]; then
        return 1
    fi

    # Try different stat formats for cross-platform compatibility
    if command -v gstat >/dev/null 2>&1; then
        # GNU stat (available via coreutils on macOS)
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec gstat -c "%Y %n" {} \; | sort -nr | head -n1 | cut -d' ' -f2-
    elif stat -c "%Y" . >/dev/null 2>&1; then
        # GNU stat (Linux)
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -c "%Y %n" {} \; | sort -nr | head -n1 | cut -d' ' -f2-
    else
        # BSD stat (macOS default)
        find "$artist_dir" -mindepth 1 -maxdepth 1 -type d -exec stat -f "%m %N" {} \; | sort -nr | head -n1 | awk '{$1=""; sub(/^ /, ""); print}'
    fi
}

# Clean metadata and set AlbumArtist - FIXED VERSION WITH PROPER TRACK TAGS
clean_metadata() {
    local artist="${1:-Various}"
    local album_dir="$2"
    local plex_release_type="${3:-album}"

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[YouMAD? DRY RUN] Would clean metadata in $album_dir and set RELEASETYPE to '$plex_release_type'"
        return 0
    fi

    if [[ -d "$album_dir" ]]; then
        # Only show this log message in verbose mode
        if [[ "$VERBOSE" == true ]]; then
            if [[ "$FORMAT" == "opus" ]]; then
                log "INFO" "YouMAD? cleaning metadata and fixing track numbers (opus format) in: $album_dir"
            else
                log "INFO" "YouMAD? cleaning metadata and fixing track numbers in: $album_dir"
            fi
        fi

        # Create a temporary file to store playlist order
        local temp_order="/tmp/youmad_playlist_order_$.txt"
        > "$temp_order"

        # First pass: collect all files and sort them by creation time to preserve playlist order
        find "$album_dir" -name "temp_*.${FORMAT}" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | \
        sort -n | cut -d' ' -f2- > "$temp_order" 2>/dev/null

        # If stat -c doesn't work (macOS), try BSD stat
        if [[ ! -s "$temp_order" ]]; then
            find "$album_dir" -name "temp_*.${FORMAT}" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
            sort -n | awk '{$1=""; sub(/^ /, ""); print}' > "$temp_order" 2>/dev/null
        fi

        # If still no files, try without temp_ prefix
        if [[ ! -s "$temp_order" ]]; then
            find "$album_dir" -name "*.${FORMAT}" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | \
            sort -n | cut -d' ' -f2- > "$temp_order" 2>/dev/null
            
            # BSD stat fallback
            if [[ ! -s "$temp_order" ]]; then
                find "$album_dir" -name "*.${FORMAT}" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
                sort -n | awk '{$1=""; sub(/^ /, ""); print}' > "$temp_order" 2>/dev/null
            fi
        fi

        # If we still have no ordered list, just use alphabetical order
        if [[ ! -s "$temp_order" ]]; then
            find "$album_dir" -name "*.${FORMAT}" -type f | sort > "$temp_order"
        fi

        # Process files in playlist order
        local counter=1
        while IFS= read -r file; do
            [[ ! -f "$file" ]] && continue
            
            local filename=$(basename "$file")
            local title=""
            
            # Extract title from filename
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
            
            local new_name
            new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$FORMAT")
            local new_path="$album_dir/$new_name"
            
            # Rename file if needed
            if [[ "$file" != "$new_path" ]]; then
                if mv "$file" "$new_path" 2>/dev/null; then
                    if [[ "$VERBOSE" == true ]]; then
                        log "INFO" "YouMAD? renamed: $filename -> $new_name"
                    fi
                else
                    log "WARN" "YouMAD? failed to rename: $filename"
                    new_path="$file"
                fi
            fi
            
            # Set proper metadata based on format
            if [[ "$FORMAT" == "opus" ]]; then
                # Use opustags for opus files - get album name from directory
                local album_name=$(basename "$album_dir")
                # Clean up album name (remove sanitization artifacts)
                album_name=$(echo "$album_name" | sed 's/_/ /g')
                
                local temp_opus="/tmp/youmad_opus_temp_$$.opus"
                
                if opustags "$new_path" \
                    --delete-all \
                    --add "TITLE=$title" \
                    --add "ARTIST=$artist" \
                    --add "ALBUM=$album_name" \
                    --add "ALBUMARTIST=$artist" \
                    --add "TRACKNUMBER=$counter" \
                    --add "RELEASETYPE=$plex_release_type" \
                    -o "$temp_opus" >/dev/null 2>&1; then
                    
                    if mv "$temp_opus" "$new_path" 2>/dev/null; then
                        if [[ "$VERBOSE" == true ]]; then
                            log "INFO" "YouMAD? set opus track $counter metadata for: $(basename "$new_path")"
                        fi
                    else
                        log "WARN" "YouMAD? failed to update opus metadata for: $(basename "$new_path")"
                        rm -f "$temp_opus"
                    fi
                else
                    log "WARN" "YouMAD? failed to set opus metadata for: $(basename "$new_path")"
                    rm -f "$temp_opus"
                fi
                
            elif [[ "$FORMAT" == "m4a" ]]; then
                # For M4A files, use iTunes-compatible tags
                exiftool -overwrite_original \
                    -Track="$counter" \
                    -TrackNumber="$counter" \
                    -Title="$title" \
                    -AlbumArtist="$artist" \
                    -RELEASETYPE="$plex_release_type" \
                    -Description= -LongDescription= -Comment= \
                    "$new_path" >/dev/null 2>&1 || \
                log "WARN" "YouMAD? failed to set metadata for: $(basename "$new_path")"
                
                if [[ "$VERBOSE" == true ]]; then
                    log "INFO" "YouMAD? set track $counter metadata for: $(basename "$new_path")"
                fi
                
            else
                # For other formats, use ID3 tags
                exiftool -overwrite_original \
                    -Track="$counter" \
                    -TRCK="$counter" \
                    -Title="$title" \
                    -AlbumArtist="$artist" \
                    -RELEASETYPE="$plex_release_type" \
                    -Description= -LongDescription= -Comment= \
                    "$new_path" >/dev/null 2>&1 || \
                log "WARN" "YouMAD? failed to set metadata for: $(basename "$new_path")"
                
                if [[ "$VERBOSE" == true ]]; then
                    log "INFO" "YouMAD? set track $counter metadata for: $(basename "$new_path")"
                fi
            fi
            
            ((counter++))
            
        done < "$temp_order"

        rm -f "$temp_order"
        
        # Only show completion message in verbose mode
        if [[ "$VERBOSE" == true ]]; then
            if [[ "$FORMAT" == "opus" ]]; then
                log "INFO" "YouMAD? opus track numbering and metadata completed for $((counter-1)) files"
            else
                log "INFO" "YouMAD? track numbering and metadata completed for $((counter-1)) files"
            fi
        fi
    else
        log "WARN" "YouMAD? album directory not found: $album_dir"
    fi
}

# Get album information from URL
get_album_info() {
    local url="$1"
    local temp_json="/tmp/youmad_info_$$.json"

    # Check if timeout command is available
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 30"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 30"
    fi

    # Use timeout to prevent hanging (if available)
    if [[ -n "$timeout_cmd" ]]; then
        if $timeout_cmd yt-dlp --dump-json --flat-playlist --no-warnings --quiet "$url" > "$temp_json" 2>"$temp_json.err"; then
            local success=true
        else
            local success=false
        fi
    else
        if yt-dlp --dump-json --flat-playlist --no-warnings --quiet "$url" > "$temp_json" 2>"$temp_json.err"; then
            local success=true
        else
            local success=false
        fi
    fi

    if [[ "$success" == "true" ]]; then
        # Check if temp_json has content
        if [[ ! -s "$temp_json" ]]; then
            rm -f "$temp_json" "$temp_json.err"
            echo "Unknown Album"
            return 1
        fi

        # Extract just the album title
        local album_title
        album_title=$(jq -r '
            if type == "array" then
                (.[0].playlist // .[0].album // "Unknown Album")
            else
                (.playlist // .album // .title // "Unknown Album")
            end' "$temp_json" 2>/dev/null | head -1)

        # Clean up album title
        if [[ "$album_title" == "null" || -z "$album_title" ]]; then
            album_title="Unknown Album"
        fi

        rm -f "$temp_json" "$temp_json.err"
        echo "$album_title"
        return 0
    else
        rm -f "$temp_json" "$temp_json.err"
        echo "Unknown Album"
        return 1
    fi
}

# Download or analyze a single album using individual track approach - SIMPLIFIED VERSION
download_album() {
    local url="$1"
    local artist="${2:-Unknown Artist}"
    local line_num="${3:-}"
    local plex_release_type="${4:-album}"

    # Additional sanitization for filesystem safety
    local artist_clean="${artist//&/and}"
    artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')

    if [[ "$DRY_RUN" == true ]]; then
        local album_title
        album_title=$(get_album_info "$url")

        if [[ "$album_title" != "Unknown Album" ]]; then
            if [[ "$VERBOSE" == true ]]; then
                log "INFO" "YouMAD? would download '$album_title' by '$artist'"
            else
                printf "  Would download: %s - %s\n" "$artist" "$album_title"
            fi
        else
            log "WARN" "YouMAD? failed to get album info for '$artist' - URL may be invalid"
        fi
        return 0
    fi

    # Get album info for display
    local album_title
    album_title=$(get_album_info "$url")

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "YouMAD? starting download for $artist: $url"
        log "INFO" "YouMAD? extracting individual track URLs from playlist..."
    else
        printf "\n[%s/%s] %s - %s\n" "$line_num" "$(wc -l < "$URL_FILE" | tr -d ' ')" "$artist" "${album_title:-Album}"
        printf "Extracting tracks from playlist... "
    fi

    # Extract individual track URLs
    local temp_urls="/tmp/youmad_track_urls_$$.txt"

    # Record start time for duration calculation
    local start_time=$(date +%s)

    if ! yt-dlp --flat-playlist --get-url "$url" > "$temp_urls" 2>/dev/null; then
        log "ERROR" "YouMAD? failed to extract track URLs from playlist: $url"
        rm -f "$temp_urls"
        return 1
    fi

    local track_count
    track_count=$(wc -l < "$temp_urls")

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "YouMAD? found $track_count tracks to download"
    else
        printf "found %d tracks\n" "$track_count"
    fi

    if [[ "$track_count" -eq 0 ]]; then
        log "ERROR" "YouMAD? no tracks found in playlist: $url"
        rm -f "$temp_urls"
        return 1
    fi

    # Download each track individually
    local track_num=1
    local failed_tracks=0

    while IFS= read -r track_url; do
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "YouMAD? downloading track $track_num/$track_count: $track_url"
        fi

        # Prepare yt-dlp arguments with temporary filename
        local track_args=(
            --extract-audio --audio-format "$FORMAT" --audio-quality 0
            --embed-metadata --add-metadata --embed-thumbnail
            --no-mtime --limit-rate "$LIMIT_RATE"
            --sleep-interval 3 --max-sleep-interval 8
            --retries 3 --fragment-retries 3
            -o "${artist_clean}/%(album,Unknown Album|sanitize)s/temp_%(title|sanitize)s.%(ext)s"
        )

        # Add verbosity flags
        if [[ "$VERBOSE" == true ]]; then
            track_args+=(--progress)
        else
            track_args+=(--no-progress --quiet)
        fi

        # Add download archive unless overriding
        if [[ "$OVERRIDE" != true ]]; then
            track_args+=(--download-archive "$DOWNLOAD_ARCHIVE")
        fi

        # Download with appropriate output level
        if [[ "$VERBOSE" == true ]]; then
            # Full output in verbose mode
            if ! yt-dlp "${track_args[@]}" "$track_url" 2>&1 | tee -a "$ACTIVITY_LOG"; then
                log "WARN" "YouMAD? failed to download track $track_num: $track_url"
                ((failed_tracks++))
            fi
        else
            # Quiet mode - only show progress and errors
            if ! yt-dlp "${track_args[@]}" "$track_url" >> "$ACTIVITY_LOG" 2>&1; then
                log "WARN" "YouMAD? failed to download track $track_num: $track_url"
                ((failed_tracks++))
            else
                # Show simple progress indicator
                printf "  ✓ Track %d/%d downloaded\n" "$track_num" "$track_count"
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

    # Summary
    if [[ "$failed_tracks" -gt 0 ]]; then
        log "WARN" "YouMAD? download completed with $failed_tracks failed tracks for $artist"
    else
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "YouMAD? download completed successfully for $artist"
        else
            printf "  ✅ Album download completed successfully in %d minutes and %d seconds\n" "$minutes" "$seconds"
        fi
    fi

    # Find and clean metadata for latest album
    local latest_album_dir
    latest_album_dir=$(find_latest_album_dir "$artist_clean")

    if [[ -n "$latest_album_dir" ]]; then
        clean_metadata "$artist" "$latest_album_dir" "$plex_release_type"
        if [[ "$VERBOSE" != true ]]; then
            printf "  📝 Metadata updated\n"
        fi
    else
        if [[ "$VERBOSE" == true ]]; then
            log "WARN" "YouMAD? could not find album directory for metadata cleaning"
        fi
    fi

    return 0
}

# Process all URLs from file
process_urls() {
    if [[ ! -f "$URL_FILE" ]]; then
        log "ERROR" "YouMAD? $URL_FILE not found."
        exit 1
    fi

    # Clear error log for this run
    > "$ERROR_LOG"

    log "INFO" "YouMAD? processing URLs from $URL_FILE"

    # Count total valid URLs first
    local total_urls=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        total_urls=$((total_urls + 1))
    done < "$URL_FILE"

    log "INFO" "YouMAD? found $total_urls valid URLs"

    if [[ "$total_urls" -eq 0 ]]; then
        log "WARN" "YouMAD? no URLs found in $URL_FILE"
        return 0
    fi

    # Process URLs using a normal while loop
    local processed=0
    local failed=0
    local line_num=0

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Increment line number using safer arithmetic
        line_num=$((line_num + 1))

        # Parse URL, artist, and optional release type
        IFS=';' read -r url artist release_type <<< "$line"
        url="$(echo "$url" | xargs)"
        artist="$(echo "$artist" | xargs)"
        release_type="$(echo "$release_type" | xargs)"

        # Map release type abbreviation to Plex format
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

        # Validate URL format using grep instead of regex
        if ! echo "$url" | grep -q "^https\?://"; then
            log "ERROR" "YouMAD? invalid URL format: $url"
            echo "Invalid URL: $line" >> "$ERROR_LOG"
            failed=$((failed + 1))
            continue
        fi

        if [[ -z "$artist" ]]; then
            log "WARN" "YouMAD? no artist specified for URL: $url, using 'Unknown Artist'"
            artist="Unknown Artist"
        fi

        # Call download function with release type
        if download_album "$url" "$artist" "$line_num" "$plex_release_type"; then
            processed=$((processed + 1))
        else
            echo "Failed: $line" >> "$ERROR_LOG"
            failed=$((failed + 1))
        fi

        # Add delay between downloads to be respectful (but not in dry-run)
        if [[ "$DRY_RUN" != true ]]; then
            sleep 2
        fi

    done < "$URL_FILE"

    # Final summary
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "YouMAD? dry run complete: Analyzed $processed URL(s) out of $total_urls total"
        if [[ $failed -gt 0 ]]; then
            log "WARN" "YouMAD? failed to analyze $failed URL(s)"
        fi
    else
        if [[ $failed -eq 0 ]]; then
            log "INFO" "YouMAD? all downloads completed successfully. Processed $processed URLs."
        else
            log "WARN" "YouMAD? completed with some failures. Processed: $processed, Failed: $failed"
            log "WARN" "YouMAD? check $ERROR_LOG for failed downloads."
        fi
    fi
}

# Main execution
main() {
    log "INFO" "Starting YouMAD? v1.0.1"

    parse_arguments "$@"
    validate_or_create_config
    initialize_files
    check_dependencies
    process_urls

    # Handle post-processing
    if [[ "$DRY_RUN" != true && -s "$URL_FILE" ]]; then
        if [[ ! -s "$ERROR_LOG" ]]; then
            > "$URL_FILE"
            log "INFO" "YouMAD? all downloads processed successfully. $URL_FILE has been cleared."
        else
            log "WARN" "YouMAD? some downloads failed. Review $ERROR_LOG. $URL_FILE has NOT been cleared."
            echo "Failed downloads:"
            cat "$ERROR_LOG"
        fi
    elif [[ "$DRY_RUN" == true ]]; then
        log "INFO" "YouMAD? dry run complete. $URL_FILE has NOT been cleared."
    else
        log "INFO" "YouMAD? $URL_FILE was empty or contained no valid URLs."
    fi

    log "INFO" "YouMAD? session complete. Check $ACTIVITY_LOG for full details."
}

# Run main function
main "$@"
