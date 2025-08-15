#!/bin/bash
# YouMAD? - Simple Metadata Processing v2.4
# Bulletproof approach - just process every file

# Super simple metadata processing - no complex logic, just process everything
process_album_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-$(date +%Y)}"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing metadata in: $album_dir"

    # Find ALL temp files using simple approach
    local files=()
    while IFS= read -r file; do
        [[ -f "$file" ]] && files+=("$file")
    done < <(find "$album_dir" -name "temp_*" -type f \( -name "*.webm" -o -name "*.mp4" \) | sort)

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
        local new_path="$album_dir/$new_name"
        
        # Rename file
        mv "$file" "$new_path" 2>/dev/null || log "WARN" "Failed to rename: $filename"
        [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $filename → $(basename "$new_path")"
        
        # Convert WebM to Opus (container only, no re-encoding)
        if [[ "$file_ext" == "webm" ]]; then
            local opus_file="${new_path%.*}.opus"
            if ffmpeg -i "$new_path" -c:a copy "$opus_file" -y >/dev/null 2>&1; then
                rm -f "$new_path"  # Remove original WebM
                [[ "$VERBOSE" == true ]] && log "INFO" "Converted: $(basename "$new_path") → $(basename "$opus_file")"
            else
                log "WARN" "Failed to convert WebM to Opus: $(basename "$new_path")"
            fi
        fi
        
        ((counter++))
    done
    
    # Create album art from any available thumbnail
    local first_webp=$(find "$album_dir" -name "*.webp" | head -1)
    if [[ -n "$first_webp" ]]; then
        local cover_file="$album_dir/cover.jpg"
        if ffmpeg -i "$first_webp" -q:v 2 "$cover_file" -y >/dev/null 2>&1; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Created album art: cover.jpg"
            # Clean up thumbnails
            rm -f "$album_dir"/*.webp 2>/dev/null
        fi
    fi
    
    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for $((counter-1)) files"
}
