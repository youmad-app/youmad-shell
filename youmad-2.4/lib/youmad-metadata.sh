#!/bin/bash
# YouMAD? - Simple Metadata Processing v2.4
# Clean, minimal approach - just the essentials

# Simple metadata processing - just number files and convert containers
process_album_metadata() {
    local artist="$1"
    local album_dir="$2"
    local release_type="$3"
    local album_year="${4:-$(date +%Y)}"

    [[ "$VERBOSE" == true ]] && log "INFO" "Processing metadata in: $album_dir"

    # Find audio files and sort by timestamp (preserves download/playlist order)
    local temp_list="/tmp/youmad_files_$$.txt"
    if stat -c "%Y" . >/dev/null 2>&1; then
        # Linux/WSL - sort by timestamp
        find "$album_dir" -type f \( -name "*.webm" -o -name "*.mp4" -o -name "*.opus" -o -name "*.m4a" \) \
            -exec stat -c "%Y %n" {} \; | sort -n | cut -d' ' -f2- > "$temp_list"
    else
        # macOS - sort by timestamp  
        find "$album_dir" -type f \( -name "*.webm" -o -name "*.mp4" -o -name "*.opus" -o -name "*.m4a" \) \
            -exec stat -f "%m %N" {} \; | sort -n | awk '{$1=""; sub(/^ /, ""); print}' > "$temp_list"
    fi

    # Process each file in timestamp order
    local counter=1
    while IFS= read -r file; do
        [[ ! -f "$file" ]] && continue
        
        local filename=$(basename "$file")
        local file_ext="${filename##*.}"
        local title="${filename%.*}"
	title="${title#temp_}"  # Remove temp_ prefix if present

        # Create numbered filename
        local final_ext="$file_ext"
        [[ "$file_ext" == "mp4" ]] && final_ext="m4a"  # Rename MP4→M4A
        local new_name=$(printf "%02d - %s.%s" "$counter" "$title" "$final_ext")
        local new_path="$album_dir/$new_name"
        
        # Rename file
        if [[ "$file" != "$new_path" ]]; then
            mv "$file" "$new_path" 2>/dev/null || log "WARN" "Failed to rename: $filename"
            [[ "$VERBOSE" == true ]] && log "INFO" "Renamed: $filename → $(basename "$new_path")"
        fi
        
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
    done < "$temp_list"
    
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
    
    # Cleanup
    rm -f "$temp_list"
    [[ "$VERBOSE" == true ]] && log "INFO" "Metadata processing completed for $((counter-1)) files"
}
