#!/bin/bash
# YouMAD? - Fixed Metadata Processing v2.4
# Uses the exact working approach from the manual test

# Simple and bulletproof metadata processing
process_album_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-$(date +%Y)}"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing metadata in: $album_dir"

    # Use the exact approach that works in testing
    local -a files=()
    
    # Change to the album directory to ensure relative paths work
    pushd "$album_dir" >/dev/null 2>&1 || {
        log "ERROR" "Cannot access directory: $album_dir"
        return 1
    }
    
    # Use the simple approach that we know works
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files+=("$file")
            [[ "$VERBOSE" == true ]] && log "INFO" "Found file: $file"
        fi
    done < <(find . -name "temp_*" -type f \( -name "*.webm" -o -name "*.mp4" \) | sort)
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Total files found: ${#files[@]}"
    
    # If no files found, exit early
    if [[ ${#files[@]} -eq 0 ]]; then
        popd >/dev/null 2>&1
        [[ "$VERBOSE" == true ]] && log "WARN" "No temp files found in $album_dir"
        return 0
    fi

    # Process each file with a simple counter
    local counter=1
    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] && continue
        
        local filename=$(basename "$file")
        local file_ext="${filename##*.}"
        local title="${filename%.*}"
        title="${title#temp_}"  # Remove temp_ prefix
        
        # Create numbered filename
        local final_ext="$file_ext"
        [[ "$file_ext" == "mp4" ]] && final_ext="m4a"
        local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
        
        # Rename file
        if mv "$file" "$new_name" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $filename → $new_name"
        else
            log "WARN" "Failed to rename: $filename"
            continue
        fi
        
        # Convert WebM to Opus (container only, no re-encoding)
        if [[ "$file_ext" == "webm" ]]; then
            local opus_file="${new_name%.*}.opus"
            if ffmpeg -i "$new_name" -c:a copy "$opus_file" -y >/dev/null 2>&1; then
                rm -f "$new_name"  # Remove original WebM
                [[ "$VERBOSE" == true ]] && log "INFO" "Converted: $new_name → $opus_file"
            else
                log "WARN" "Failed to convert WebM to Opus: $new_name"
            fi
        fi
        
        ((counter++))
    done
    
    # Create album art from any available thumbnail
    local first_webp=$(find . -name "*.webp" | head -1)
    if [[ -n "$first_webp" && -f "$first_webp" ]]; then
        if ffmpeg -i "$first_webp" -q:v 2 "cover.jpg" -y >/dev/null 2>&1; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Created album art: cover.jpg"
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
