#!/bin/bash
# YouMAD? - Core Download Module v2.4
# Handles all yt-dlp operations and metadata fetching

# Centralized yt-dlp argument building
build_ytdlp_args() {
    local mode="$1"           # "info", "extract", "download"
    local url="$2"
    local output_template="${3:-}"  # Optional for download mode (default to empty)
    local -a args=()
    
    case "$mode" in
        "info")
            args+=(
                --dump-json
                --flat-playlist
                --no-warnings
                --quiet
            )
            ;;
        "extract")
            args+=(
                --flat-playlist
                --get-url
                --no-warnings
                --quiet
            )
            ;;
        "download")
            args+=(
                --embed-metadata
                --add-metadata
                --format "bestaudio/best"
                --no-embed-thumbnail
                --write-thumbnail
                --no-mtime
                --limit-rate "$LIMIT_RATE"
                --sleep-interval 3
                --max-sleep-interval 8
                --retries 3
                --fragment-retries 3
            )
            
            # Add output template if provided
            if [[ -n "$output_template" ]]; then
                args+=(-o "$output_template")
            fi
            
            # Add progress/quiet flags
            if [[ "${VERBOSE:-false}" == true ]]; then
                args+=(--progress)
            else
                args+=(--no-progress --quiet)
            fi
            
            # Add download archive unless overriding
            if [[ "${OVERRIDE:-false}" != true ]]; then
                args+=(--download-archive "$DOWNLOAD_ARCHIVE")
            fi
            ;;
        *)
            log "ERROR" "Unknown yt-dlp mode: $mode"
            return 1
            ;;
    esac
    
    # Return the arguments (caller will use them with yt-dlp)
    printf '%s\n' "${args[@]}"
}

# Unified metadata fetching with field selection
fetch_metadata() {
    local url="$1"
    local fields="$2"  # Comma-separated: "title", "year", "tracks", "description"
    local temp_json
    temp_json=$(create_temp_file "metadata" "json")
    
    # Get yt-dlp arguments for info mode
    local -a info_args
    readarray -t info_args < <(build_ytdlp_args "info" "$url")
    
    if ! yt-dlp "${info_args[@]}" "$url" > "$temp_json" 2>/dev/null; then
        rm -f "$temp_json"
        return 1
    fi
    
    # Parse requested fields
    local title="" year="" description="" track_count=""
    
    if [[ "$fields" == *"title"* ]]; then
        title=$(jq -r '
            if type == "array" then
                (.[0].playlist // .[0].album // .[0].title // "Unknown Album")
            else
                (.playlist // .album // .title // "Unknown Album")
            end' "$temp_json" 2>/dev/null | head -1)
        
        [[ "$title" == "null" || -z "$title" ]] && title="Unknown Album"
    fi
    
    if [[ "$fields" == *"year"* ]]; then
        # Try multiple year fields
        year=$(jq -r '
            if type == "array" then
                (.[0].release_year // .[0].upload_date // "" | tostring)
            else
                (.release_year // .upload_date // "" | tostring)
            end' "$temp_json" 2>/dev/null | head -1)
        
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
        
        # If still no year, try description
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
    
    if [[ "$fields" == *"description"* ]]; then
        description=$(jq -r '
            if type == "array" then
                (.[0].description // "")
            else
                (.description // "")
            end' "$temp_json" 2>/dev/null)
    fi
    
    if [[ "$fields" == *"tracks"* ]]; then
        if jq -e 'type == "array"' "$temp_json" >/dev/null 2>&1; then
            track_count=$(jq 'length' "$temp_json" 2>/dev/null)
        else
            track_count="1"
        fi
    fi
    
    rm -f "$temp_json"
    
    # Return results in a structured format
    echo "title=${title}|year=${year}|description=${description}|tracks=${track_count}"
}

# Extract track URLs from playlist/album
extract_track_urls() {
    local url="$1"
    local temp_urls
    temp_urls=$(create_temp_file "track_urls" "txt")
    
    # Get yt-dlp arguments for URL extraction
    local -a extract_args
    readarray -t extract_args < <(build_ytdlp_args "extract" "$url")
    
    if ! yt-dlp "${extract_args[@]}" "$url" > "$temp_urls" 2>/dev/null; then
        rm -f "$temp_urls"
        return 1
    fi
    
    local track_count
    track_count=$(wc -l < "$temp_urls")
    
    if [[ "$track_count" -eq 0 ]]; then
        rm -f "$temp_urls"
        return 1
    fi
    
    echo "$temp_urls"  # Return the temp file path
}

# Get year from individual track (fallback method)
get_track_year() {
    local track_url="$1"
    local metadata
    metadata=$(fetch_metadata "$track_url" "year")
    
    # Extract year from structured output
    if [[ "$metadata" =~ year=([^|]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Download single track with standardized arguments
download_single_track() {
    local track_url="$1"
    local output_template="$2"
    local track_num="$3"
    local total_tracks="$4"
    
    # Get yt-dlp arguments for download
    local -a download_args
    readarray -t download_args < <(build_ytdlp_args "download" "$track_url" "$output_template")
    
    # In verbose mode, show the actual yt-dlp output
    local download_success=false
    if [[ "${VERBOSE:-false}" == true ]]; then
        # Use tee to show output on console AND log it
        if yt-dlp "${download_args[@]}" "$track_url" 2>&1 | tee -a "$ACTIVITY_LOG"; then
            download_success=true
        fi
    else
        if yt-dlp "${download_args[@]}" "$track_url" >> "$ACTIVITY_LOG" 2>&1; then
            download_success=true
        fi
    fi
    
    return $([[ "$download_success" == true ]] && echo 0 || echo 1)
}

# Download album with improved metadata handling
download_album() {
    local url="$1"
    local artist="$2"
    local line_num="$3"
    local release_type="$4"

    local artist_clean="${artist//&/and}"
    artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')

    if [[ "$DRY_RUN" == true ]]; then
        local metadata
        metadata=$(fetch_metadata "$url" "title,year")
        
        # Parse structured metadata
        local album_title="" album_year=""
        if [[ "$metadata" =~ title=([^|]*) ]]; then
            album_title="${BASH_REMATCH[1]}"
        fi
        if [[ "$metadata" =~ year=([^|]*) ]]; then
            album_year="${BASH_REMATCH[1]}"
        fi
        
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download '$album_title' by '$artist' (Year: ${album_year:-Unknown})"
        else
            printf "  Would download: %s - %s (Year: %s)\n" "$artist" "$album_title" "${album_year:-Unknown}"
        fi
        return 0
    fi

    # Get album metadata
    local metadata
    metadata=$(fetch_metadata "$url" "title,year")
    
    local album_title="" album_year=""
    if [[ "$metadata" =~ title=([^|]*) ]]; then
        album_title="${BASH_REMATCH[1]}"
    fi
    if [[ "$metadata" =~ year=([^|]*) ]]; then
        album_year="${BASH_REMATCH[1]}"
    fi

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
    local temp_urls
    temp_urls=$(extract_track_urls "$url")
    
    if [[ -z "$temp_urls" ]]; then
        log "ERROR" "Failed to extract track URLs: $url"
        return 1
    fi

    local track_count
    track_count=$(wc -l < "$temp_urls")

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
    local start_time=$(date +%s)
    local output_template="${artist_clean}/%(album,Unknown Album|sanitize)s/temp_%(title|sanitize)s.%(ext)s"

    while IFS= read -r track_url; do
        if [[ "${VERBOSE:-false}" == true ]]; then
            log "INFO" "Starting download of track $track_num/$track_count"
        fi
        
        if download_single_track "$track_url" "$output_template" "$track_num" "$track_count"; then
            if [[ "${VERBOSE:-false}" == true ]]; then
                log "INFO" "Successfully downloaded track $track_num/$track_count"
            else
                printf "  ✓ Track %d/%d\n" "$track_num" "$track_count"
            fi
        else
            # Check if files were actually downloaded despite error
            local track_files
            track_files=$(find "${artist_clean}" -name "temp_*" -type f \( -name "*.mp4" -o -name "*.webm" -o -name "*.opus" -o -name "*.m4a" \) 2>/dev/null | wc -l)
            if [[ "$track_files" -gt 0 ]]; then
                if [[ "$VERBOSE" == true ]]; then
                    log "WARN" "Track $track_num/$track_count downloaded with warnings"
                else
                    printf "  ✓ Track %d/%d (with warnings)\n" "$track_num" "$track_count"
                fi
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

    # Return album info for metadata processing
    echo "album_dir=$(find_latest_album_dir "$artist_clean")|year=$album_year"
    return 0
}

# Download playlist with simple cleanup
download_playlist() {
    local url="$1"
    local playlist_name="$2"
    local line_num="$3"

    if [[ "$DRY_RUN" == true ]]; then
        local metadata
        metadata=$(fetch_metadata "$url" "title")
        
        local playlist_title=""
        if [[ "$metadata" =~ title=([^|]*) ]]; then
            playlist_title="${BASH_REMATCH[1]}"
        fi
        
        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "Would download playlist '$playlist_title'"
        else
            printf "  Would download playlist: %s\n" "$playlist_title"
        fi
        return 0
    fi

    # TODO: Implement full playlist download logic
    # For now, just log that we're starting
    log "INFO" "Starting playlist download: $url"
    return 0
}
