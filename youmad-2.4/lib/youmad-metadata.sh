#!/bin/bash
# YouMAD? - Metadata Processing Module v2.4
# Handles all post-download file processing and metadata operations

# Process all audio files in an album directory
process_album_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-}"

    if [[ "$DRY_RUN" == true ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "[DRY RUN] Would process metadata in $album_dir"
        return 0
    fi

    if [[ ! -d "$album_dir" ]]; then
        log "WARN" "Album directory not found: $album_dir"
        return 1
    fi

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing metadata in: $album_dir"

    # Get album name from directory
    local album_name=$(basename "$album_dir" | sed 's/_/ /g')

    # Determine year to use
    local year
    year=$(determine_album_year "$album_dir" "$album_year")
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Using year: $year for album: $album_name"
    printf "" >/dev/null  # Silent sync point

    # Get sorted list of audio files
    local temp_order
    temp_order=$(get_sorted_audio_files "$album_dir")
    printf "" >/dev/null  # Silent sync point

    if [[ ! -s "$temp_order" ]]; then
        log "WARN" "No audio files found in $album_dir"
        rm -f "$temp_order"
        return 1
    fi

    # Read files into array
    declare -a files_array
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files_array+=("$file")
        fi
    done < "$temp_order"
    printf "" >/dev/null  # Silent sync point

    # Debug output
    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Found ${#files_array[@]} audio files to process:"
        for i in "${!files_array[@]}"; do
            log "INFO" "  $((i+1)). $(basename "${files_array[i]}")"
        done
    fi

    # Process each file
    process_audio_files_array files_array "$artist" "$album_name" "$release_type" "$year" "$album_dir"

    printf "" >/dev/null  # Silent sync point (critical)

    rm -f "$temp_order"
    printf "" >/dev/null  # Silent sync point

    # Final cleanup
    cleanup_temp_files_in_directory "$album_dir"
    printf "" >/dev/null  # Silent sync point

    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for ${#files_array[@]} files"
    printf "" >/dev/null  # Silent sync point
    return 0
}

# Determine the best year to use for the album
determine_album_year() {
    local album_dir="$1"
    local provided_year="$2"
    local album_name=$(basename "$album_dir" | sed 's/_/ /g')
    
    # Use provided year if available
    if [[ -n "$provided_year" ]]; then
        echo "$provided_year"
        return 0
    fi
    
    # Try to extract from album name
    if [[ "$album_name" =~ [[:space:]]([0-9]{4})[[:space:]]* ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    elif [[ "$album_name" =~ ([0-9]{4}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Final fallback to current year
    date +%Y
}

# Get sorted list of audio files in directory
get_sorted_audio_files() {
    local directory="$1"
    local temp_order
    temp_order=$(sort_files_by_time "$directory" "temp_*")

    # Fallback for any audio files if no temp_ files found
    if [[ ! -s "$temp_order" ]]; then
        [[ "$VERBOSE" == true ]] && log "INFO" "No temp_ files found, searching for any audio files"
        rm -f "$temp_order"
        temp_order=$(sort_files_by_time "$directory" "*")
    fi

    echo "$temp_order"
}

# Process array of audio files
process_audio_files_array() {
    local -n files_ref=$1
    local artist="$2"
    local album_name="$3"
    local release_type="$4"
    local year="$5"
    local album_dir="$6"

    printf "" >/dev/null  # Silent sync point

    for i in "${!files_ref[@]}"; do
        local file="${files_ref[i]}"
        local counter=$((i + 1))

        [[ ! -f "$file" ]] && continue

        local filename=$(basename "$file")
        local file_ext="${filename##*.}"

        # Skip metadata files
        [[ "$file_ext" == "metadata" ]] && continue
        
        [[ "$VERBOSE" == true ]] && log "INFO" "Processing file $counter: $filename (type: $file_ext)"
        printf "" >/dev/null  # Silent sync point

        # Extract and clean title
        local title
        title=$(extract_track_title "$filename" "$counter")
        local original_title="$title"
        printf "" >/dev/null  # Silent sync point

        # Rename file with track number
        local current_file
        current_file=$(rename_track_file "$file" "$title" "$counter" "$file_ext" "$album_dir")
        printf "" >/dev/null  # Silent sync point

        # Process based on file type
        process_audio_file_by_type "$current_file" "$file_ext" "$title" "$original_title" "$artist" "$album_name" "$release_type" "$year" "$counter" "$album_dir"
        printf "" >/dev/null  # Silent sync point
    done
    
    printf "" >/dev/null  # Silent sync point
}

# Extract track title from filename
extract_track_title() {
    local filename="$1"
    local track_number="$2"
    
    if [[ "$filename" =~ ^temp_(.*)\.[^.]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "Track $track_number"
    fi
}

# Rename track file with proper numbering
rename_track_file() {
    local file="$1"
    local title="$2"
    local counter="$3"
    local file_ext="$4"
    local album_dir="$5"
    
    # Determine final extension
    local final_ext="$file_ext"
    [[ "$file_ext" == "mp4" ]] && final_ext="m4a"

    local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
    local new_path="$album_dir/$new_name"

    if [[ "$file" != "$new_path" ]]; then
        if mv "$file" "$new_path" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $(basename "$file") -> $new_name"
            echo "$new_path"
        else
            log "WARN" "Failed to rename: $(basename "$file")"
            echo "$file"
        fi
    else
        echo "$file"
    fi
}

# Process individual audio file based on its type
process_audio_file_by_type() {
    local current_file="$1"
    local file_ext="$2"
    local title="$3"
    local original_title="$4"
    local artist="$5"
    local album_name="$6"
    local release_type="$7"
    local year="$8"
    local counter="$9"
    local album_dir="${10}"

    case "$file_ext" in
        "webm")
            process_webm_file "$current_file" "$title" "$original_title" "$artist" "$album_name" "$release_type" "$year" "$counter" "$album_dir"
            ;;
        "mp4")
            process_mp4_file "$current_file" "$title" "$original_title" "$artist" "$album_name" "$release_type" "$year" "$counter" "$album_dir"
            ;;
        "opus")
            process_opus_file "$current_file" "$title" "$artist" "$album_name" "$release_type" "$year" "$counter"
            ;;
        "m4a")
            process_m4a_file "$current_file" "$title" "$artist" "$album_name" "$year" "$counter"
            ;;
    esac
}

# Process WebM files - convert to Opus
process_webm_file() {
    local current_file="$1"
    local title="$2"
    local original_title="$3"
    local artist="$4"
    local album_name="$5"
    local release_type="$6"
    local year="$7"
    local counter="$8"
    local album_dir="$9"

    [[ "$VERBOSE" == true ]] && log "INFO" "Converting WebM to Opus: $(basename "$current_file")"
    printf "" >/dev/null  # Silent sync point

    # Get original performer
    local original_performer
    original_performer=$(extract_performer_from_file "$current_file")
    printf "" >/dev/null  # Silent sync point

    # Process thumbnail if exists
    process_thumbnail "$album_dir" "$original_title"
    printf "" >/dev/null  # Silent sync point

    # Convert to Opus with metadata
    convert_webm_to_opus "$current_file" "$title" "$artist" "$album_name" "$release_type" "$year" "$counter" "$original_performer"
    printf "" >/dev/null  # Silent sync point
}

# Process MP4 files - set metadata and rename to M4A
process_mp4_file() {
    local current_file="$1"
    local title="$2"
    local original_title="$3"
    local artist="$4"
    local album_name="$5"
    local release_type="$6"
    local year="$7"
    local counter="$8"
    local album_dir="$9"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing MP4 file: $(basename "$current_file")"

    # Get original performer
    local original_performer
    original_performer=$(extract_performer_from_file "$current_file")

    # Process thumbnail if exists
    process_thumbnail "$album_dir" "$original_title"

    # Update MP4 metadata
    update_mp4_metadata "$current_file" "$title" "$artist" "$album_name" "$release_type" "$year" "$counter" "$original_performer"
}

# Process existing Opus files
process_opus_file() {
    local current_file="$1"
    local title="$2"
    local artist="$3"
    local album_name="$4"
    local release_type="$5"
    local year="$6"
    local counter="$7"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing existing Opus file: $(basename "$current_file")"
    # Opus files are typically already properly formatted
}

# Process M4A files with exiftool
process_m4a_file() {
    local current_file="$1"
    local title="$2"
    local artist="$3"
    local album_name="$4"
    local year="$5"
    local counter="$6"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing M4A file: $(basename "$current_file")"
    exiftool -overwrite_original -Track="$counter" -Title="$title" -Artist="$artist" -Album="$album_name" -Year="$year" "$current_file" >/dev/null 2>&1
}

# Extract performer information from audio file
extract_performer_from_file() {
    local file="$1"
    local performer=""
    
    performer=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    [[ -z "$performer" ]] && performer=$(ffprobe -v quiet -show_entries format_tags=performer -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    echo "$performer"
}

# Process thumbnail files
process_thumbnail() {
    local album_dir="$1"
    local original_title="$2"
    local temp_thumbnail="$album_dir/temp_${original_title}.webp"
    
    printf "" >/dev/null  # Silent sync point
    
    if [[ -f "$temp_thumbnail" ]]; then
        local cover_file="$album_dir/cover.jpg"
        if ffmpeg -i "$temp_thumbnail" -vf "crop=min(iw\,ih):min(iw\,ih)" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Saved album art as: $(basename "$cover_file")"
            printf "" >/dev/null  # Silent sync point
            rm -f "$temp_thumbnail"
            [[ "$VERBOSE" == true ]] && log "INFO" "Cleaned up thumbnail: $(basename "$temp_thumbnail")"
            printf "" >/dev/null  # Silent sync point
        fi
    fi
    printf "" >/dev/null  # Silent sync point
}

# Convert WebM to Opus with full metadata
convert_webm_to_opus() {
    local current_file="$1"
    local title="$2"
    local artist="$3"
    local album_name="$4"
    local release_type="$5"
    local year="$6"
    local counter="$7"
    local original_performer="$8"

    printf "" >/dev/null  # Silent sync point
    local opus_file="${current_file%.*}.opus"
    printf "" >/dev/null  # Silent sync point
    
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
        printf "" >/dev/null  # Silent sync point
    else
        convert_cmd+=(-metadata:s:a:0 PERFORMER="$artist")
        printf "" >/dev/null  # Silent sync point
    fi

    convert_cmd+=("$opus_file")
    printf "" >/dev/null  # Silent sync point (critical before ffmpeg)

    if "${convert_cmd[@]}" >/dev/null 2>&1; then
        printf "" >/dev/null  # Silent sync point
        rm -f "$current_file"
        printf "" >/dev/null  # Silent sync point
        [[ "$VERBOSE" == true ]] && log "INFO" "Converted WebM to Opus for track $counter"
        printf "" >/dev/null  # Silent sync point
    else
        log "WARN" "Failed to convert WebM to Opus for: $(basename "$current_file")"
        printf "" >/dev/null  # Silent sync point
    fi
}

# Update MP4 metadata
update_mp4_metadata() {
    local current_file="$1"
    local title="$2"
    local artist="$3"
    local album_name="$4"
    local release_type="$5"
    local year="$6"
    local counter="$7"
    local original_performer="$8"

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
}

# Clean up temporary files in album directory
cleanup_temp_files_in_directory() {
    local album_dir="$1"
    
    find "$album_dir" -name "*.metadata" -delete 2>/dev/null
    printf "" >/dev/null  # Silent sync point
    
    find "$album_dir" -name "temp_*.webp" -delete 2>/dev/null  
    printf "" >/dev/null  # Silent sync point
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Cleaned up any remaining temp files"
    printf "" >/dev/null  # Silent sync point
}
