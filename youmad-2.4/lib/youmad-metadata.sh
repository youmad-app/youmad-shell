#!/bin/bash
# YouMAD? - Stage 1 Metadata Processing v2.4
# Core metadata extraction and application

# Extract original metadata from downloaded file using ffprobe
extract_original_metadata() {
    local file="$1"
    
    # Extract key metadata fields from the downloaded file
    local album title performer composer date
    
    album=$(ffprobe -v quiet -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    title=$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    performer=$(ffprobe -v quiet -show_entries format_tags=performer -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    composer=$(ffprobe -v quiet -show_entries format_tags=composer -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    # Try multiple date/year fields
    date=$(ffprobe -v quiet -show_entries format_tags=date -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    [[ -z "$date" ]] && date=$(ffprobe -v quiet -show_entries format_tags=year -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    [[ -z "$date" ]] && date=$(ffprobe -v quiet -show_entries format_tags=release_date -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    # Simple year extraction - just take first 4 digits if we have a date
    local year=""
    if [[ -n "$date" && "$date" =~ ([0-9]{4}) ]]; then
        year="${BASH_REMATCH[1]}"
    fi
    
    # If no performer, try artist field as fallback
    [[ -z "$performer" ]] && performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    # Return structured metadata (pipe-separated to avoid conflicts)
    echo "album=${album}|title=${title}|performer=${performer}|composer=${composer}|year=${year}"
}

# Convert WebM to Opus with complete metadata
convert_webm_to_opus_with_metadata() {
    local webm_file="$1"
    local opus_file="$2"
    local track_num="$3"
    local album_artist="$4"    # From urls.txt
    local release_type="$5"    # Converted plex_release_type
    
    # Extract original YouTube Music metadata
    local orig_metadata
    orig_metadata=$(extract_original_metadata "$webm_file")
    
    # Parse the extracted metadata
    local yt_album yt_title yt_performer yt_composer yt_year
    while IFS='|' read -r field; do
        case "$field" in
            album=*) yt_album="${field#*=}" ;;
            title=*) yt_title="${field#*=}" ;;
            performer=*) yt_performer="${field#*=}" ;;
            composer=*) yt_composer="${field#*=}" ;;
            year=*) yt_year="${field#*=}" ;;
        esac
    done <<< "${orig_metadata//|/$'\n'}"
    
    # Use YouTube Music data as primary source, with fallbacks
    local final_album="${yt_album:-Unknown Album}"
    local final_title="${yt_title:-Track $track_num}"
    local final_performer="${yt_performer:-$album_artist}"
    local final_composer="${yt_composer:-$album_artist}"
    local final_year="${yt_year:-$(date +%Y)}"  # Simple fallback to current year
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus with metadata:"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Album: $final_album (from YT Music)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Title: $final_title (from YT Music)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Performer: $final_performer (from YT Music)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Composer: $final_composer (from YT Music)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Album Artist: $album_artist (from urls.txt)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Release Type: $release_type (from urls.txt)"
    [[ "$VERBOSE" == true ]] && log "INFO" "  Year: $final_year"
    
    # Convert WebM to Opus with comprehensive metadata (following 2.1.3 pattern)
    local ffmpeg_cmd=(
        ffmpeg -i "$webm_file" 
        -c:a copy 
        -map_metadata -1  # Clear all existing metadata first
        -metadata:s:a:0 TITLE="$final_title"
        -metadata:s:a:0 ALBUM="$final_album"
        -metadata:s:a:0 ARTIST="$album_artist"
        -metadata:s:a:0 ALBUMARTIST="$album_artist"
        -metadata:s:a:0 PERFORMER="$final_performer"
        -metadata:s:a:0 COMPOSER="$final_composer"
        -metadata:s:a:0 TRACKNUMBER="$track_num"
        -metadata:s:a:0 DATE="$final_year"
        -metadata:s:a:0 RELEASETYPE="$release_type"
        "$opus_file"
        -y
    )
    
    if "${ffmpeg_cmd[@]}" >/dev/null 2>&1; then
        [[ "$VERBOSE" == true ]] && log "INFO" "Successfully converted WebM to Opus with metadata"
        return 0
    else
        log "WARN" "Failed to convert WebM to Opus: $(basename "$webm_file")"
        return 1
    fi
}

# Apply metadata to M4A files (converted from MP4)
apply_m4a_metadata() {
    local m4a_file="$1"
    local track_num="$2"
    local album_artist="$3"
    local release_type="$4"
    
    # Extract original metadata from the M4A file
    local orig_metadata
    orig_metadata=$(extract_original_metadata "$m4a_file")
    
    # Parse the extracted metadata (same logic as WebM)
    local yt_album yt_title yt_performer yt_composer yt_year
    while IFS='|' read -r field; do
        case "$field" in
            album=*) yt_album="${field#*=}" ;;
            title=*) yt_title="${field#*=}" ;;
            performer=*) yt_performer="${field#*=}" ;;
            composer=*) yt_composer="${field#*=}" ;;
            year=*) yt_year="${field#*=}" ;;
        esac
    done <<< "${orig_metadata//|/$'\n'}"
    
    # Same fallback logic as Opus
    local final_album="${yt_album:-Unknown Album}"
    local final_title="${yt_title:-Track $track_num}"
    local final_performer="${yt_performer:-$album_artist}"
    local final_composer="${yt_composer:-$album_artist}"
    local final_year="${yt_year:-$(date +%Y)}"
    
    # Create temporary file for metadata update
    local temp_m4a="/tmp/youmad_m4a_$$.m4a"
    
    # Apply metadata to M4A (following 2.1.3 pattern)
    local ffmpeg_cmd=(
        ffmpeg -i "$m4a_file"
        -c copy
        -map_metadata -1  # Clear existing metadata
        -metadata TITLE="$final_title"
        -metadata ALBUM="$final_album"
        -metadata ARTIST="$album_artist"
        -metadata ALBUMARTIST="$album_artist"
        -metadata PERFORMER="$final_performer"
        -metadata COMPOSER="$final_composer"
        -metadata TRACK="$track_num"
        -metadata DATE="$final_year"
        -metadata RELEASETYPE="$release_type"
        "$temp_m4a"
        -y
    )
    
    if "${ffmpeg_cmd[@]}" >/dev/null 2>&1; then
        mv "$temp_m4a" "$m4a_file"
        [[ "$VERBOSE" == true ]] && log "INFO" "Applied M4A metadata successfully"
        return 0
    else
        rm -f "$temp_m4a"
        log "WARN" "Failed to apply M4A metadata: $(basename "$m4a_file")"
        return 1
    fi
}

# Main metadata processing function (Stage 1)
process_album_metadata() {
    local album_artist="$1"     # From urls.txt (Album Artist)
    local album_dir="$2"
    local release_type="$3"     # Converted plex_release_type from urls.txt
    local album_year="${4:-$(date +%Y)}"  # Currently unused in Stage 1, keeping for compatibility

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing metadata in: $album_dir"
    [[ "$VERBOSE" == true ]] && log "INFO" "Album Artist (from urls.txt): $album_artist"
    [[ "$VERBOSE" == true ]] && log "INFO" "Release Type: $release_type"

    # Change to the album directory
    pushd "$album_dir" >/dev/null 2>&1 || {
        log "ERROR" "Cannot access directory: $album_dir"
        return 1
    }
    
    # Find all temp files using timestamp-based sorting to preserve YouTube Music order
    local temp_order
    temp_order=$(sort_files_by_time "." "temp_*")
    
    local -a files=()
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files+=("$file")
            [[ "$VERBOSE" == true ]] && log "INFO" "Found file: $file"
        fi
    done < "$temp_order"
    
    # Clean up the temp order file
    rm -f "$temp_order"
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Total files found: ${#files[@]}"
    
    # If no files found, exit early
    if [[ ${#files[@]} -eq 0 ]]; then
        popd >/dev/null 2>&1
        [[ "$VERBOSE" == true ]] && log "WARN" "No temp files found in $album_dir"
        return 0
    fi

    # Process each file with complete metadata
    local counter=1
    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] && continue
        
        local filename=$(basename "$file")
        local file_ext="${filename##*.}"
        local title="${filename%.*}"
        title="${title#temp_}"  # Remove temp_ prefix
        
        # Process based on file type
        case "$file_ext" in
            "webm")
                local opus_file=$(printf "%02d - %s.opus" "$counter" "$title")
                
                # Convert with complete metadata extraction and application
                if convert_webm_to_opus_with_metadata "$file" "$opus_file" "$counter" "$album_artist" "$release_type"; then
                    rm -f "$file"  # Remove original WebM
                    [[ "$VERBOSE" == true ]] && log "INFO" "Converted: $filename → $opus_file"
                else
                    log "WARN" "Conversion failed: $filename"
                fi
                ;;
            "mp4")
                # Rename to M4A first
                local m4a_file=$(printf "%02d - %s.m4a" "$counter" "$title")
                if mv "$file" "$m4a_file" 2>/dev/null; then
                    [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $filename → $m4a_file"
                    
                    # Apply metadata
                    if apply_m4a_metadata "$m4a_file" "$counter" "$album_artist" "$release_type"; then
                        [[ "$VERBOSE" == true ]] && log "INFO" "Applied metadata: $m4a_file"
                    fi
                else
                    log "WARN" "Failed to rename: $filename"
                fi
                ;;
        esac
        
        ((counter++))
    done
    
    # Create album art from any available thumbnail with square cropping
    local first_webp=$(find . -name "*.webp" | head -1)
    if [[ -n "$first_webp" && -f "$first_webp" ]]; then
        # Crop to square to remove 16:9 padding, using the smaller dimension
        if ffmpeg -i "$first_webp" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "cover.jpg" -y >/dev/null 2>&1; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Created square album art: cover.jpg"
            # Clean up thumbnails
            rm -f ./*.webp 2>/dev/null
        fi
    fi
    
    # Return to original directory
    popd >/dev/null 2>&1
    
    local processed_count=$((counter-1))
    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for $processed_count files"
    
    return 0
}
