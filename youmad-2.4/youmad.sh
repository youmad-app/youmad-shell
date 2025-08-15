#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.4

set -euo pipefail

# Get script directory for reliable sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
if [[ -f "$SCRIPT_DIR/lib/youmad-utils.sh" ]]; then
    source "$SCRIPT_DIR/lib/youmad-utils.sh"
else
    echo "ERROR: Cannot find lib/youmad-utils.sh"
    exit 1
fi

if [[ -f "$SCRIPT_DIR/lib/youmad-core.sh" ]]; then
    source "$SCRIPT_DIR/lib/youmad-core.sh"
else
    echo "ERROR: Cannot find lib/youmad-core.sh"
    exit 1
fi

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

# NOTE: Core download functions (get_album_info, get_track_year, download_album, download_playlist)
# are now in youmad-core.sh

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

    # Use the new cross-platform file sorting
    local temp_order
    temp_order=$(sort_files_by_time "$album_dir" "temp_*")

    # Fallback for any audio files if no temp_ files found
    if [[ ! -s "$temp_order" ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "No temp_ files found, searching for any audio files"
        rm -f "$temp_order"
        temp_order=$(sort_files_by_time "$album_dir" "*")
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
                local temp_m4a
                temp_m4a=$(create_temp_file "m4a" "m4a")
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
        
        # Parse line using the robust method from utils
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

        # Validate URL using utils function
        if ! validate_url "$url"; then
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

            # Download album and get result info
            local download_result
	    [[ "$VERBOSE" == true ]] && log "INFO" "DEBUG: About to call download_album from youmad-core.sh"
            #download_result=$(download_album "$url" "$artist" "$line_num/$total_urls" "$plex_release_type")

	    # Call download_album directly (not in subshell) so verbose output shows
	    download_album "$url" "$artist" "$line_num/$total_urls" "$plex_release_type"
	    local download_exit_code=$?

	    # Get the album info for metadata processing
	    local artist_clean="${artist//&/and}"
	    artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')
	    local latest_album_dir
	    latest_album_dir=$(find_latest_album_dir "$artist_clean")
	    local download_result="album_dir=$latest_album_dir|year="
            
            if [[ $download_exit_code -eq 0 ]]; then
                processed=$((processed + 1))
                
                # Extract album directory and year from download result
                local album_dir="" album_year=""
                if [[ "$download_result" =~ album_dir=([^|]*) ]]; then
                    album_dir="${BASH_REMATCH[1]}"
                fi
                if [[ "$download_result" =~ year=([^|]*) ]]; then
                    album_year="${BASH_REMATCH[1]}"
                fi
                
                # Process metadata if we have a valid album directory
                if [[ -n "$album_dir" && -d "$album_dir" ]]; then
                    clean_metadata "$artist" "$album_dir" "$plex_release_type" "$album_year"
                    [[ "$VERBOSE" != true ]] && printf "  📝 Metadata updated (Year: %s)\n" "${album_year:-$(date +%Y)}"
                else
                    log "WARN" "Could not find album directory for metadata processing"
                fi
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
    log "INFO" "Starting YouMAD? v2.4"

    parse_arguments "$@"
    load_config
    initialize_files
    
    if ! check_dependencies; then
        exit 1
    fi
    
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

    # Cleanup temp files before exit
    cleanup_temp_files
    
    log "INFO" "Session complete. Check $ACTIVITY_LOG for details."
}

# Run main
main "$@"
