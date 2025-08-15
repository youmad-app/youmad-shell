#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.4

set -euo pipefail

# Get script directory for reliable sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules in dependency order
if [[ -f "$SCRIPT_DIR/lib/youmad-config.sh" ]]; then
    source "$SCRIPT_DIR/lib/youmad-config.sh"
else
    echo "ERROR: Cannot find lib/youmad-config.sh"
    exit 1
fi

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

if [[ -f "$SCRIPT_DIR/lib/youmad-metadata.sh" ]]; then
    source "$SCRIPT_DIR/lib/youmad-metadata.sh"
else
    echo "ERROR: Cannot find lib/youmad-metadata.sh"
    exit 1
fi

# Options (will be set by parse_arguments)
DRY_RUN=false
OVERRIDE=false
VERBOSE=false

# Parse command-line arguments
parse_arguments() {
    for arg in "$@"; do
        case "$arg" in
            --config)
                # Initialize environment first
                initialize_environment
                create_interactive_config
                exit $?
                ;;
            --show-config)
                initialize_environment
                if load_config; then
                    show_config
                    exit 0
                else
                    echo "ERROR: Failed to load configuration"
                    exit 1
                fi
                ;;
            --reset-config)
                initialize_environment
                if reset_config; then
                    echo "Configuration reset to defaults"
                    exit 0
                else
                    echo "ERROR: Failed to reset configuration"
                    exit 1
                fi
                ;;
            --docker-init)
                if init_docker_config; then
                    echo "Docker configuration initialized"
                    exit 0
                else
                    echo "ERROR: Failed to initialize Docker configuration"
                    exit 1
                fi
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --override)
                OVERRIDE=true
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown argument: $arg"
                show_usage
                exit 1
                ;;
        esac
    done
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
            download_album "$url" "$artist" "$line_num/$total_urls" "$plex_release_type"
            local download_exit_code=$?

            if [[ $download_exit_code -eq 0 ]]; then
                processed=$((processed + 1))
                
                # Get album directory for metadata processing
                local artist_clean="${artist//&/and}"
                artist_clean=$(echo "$artist_clean" | tr -d '/<>:"|?*' | tr ' ' '_')
                local album_dir
                album_dir=$(find_latest_album_dir "$artist_clean")
                local album_year="2021"  # This should be extracted properly

                # Process metadata if we have a valid album directory
                if [[ -n "$album_dir" && -d "$album_dir" ]]; then
                    # Silent synchronization point (anti-Heisenbug)
                    printf "" >/dev/null
                    process_album_metadata "$artist" "$album_dir" "$plex_release_type" "$album_year"
                    printf "" >/dev/null
                    [[ "$VERBOSE" != true ]] && echo "  📝 Metadata updated"
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
    # Parse arguments first (some may exit immediately)
    parse_arguments "$@"
    
    # Initialize environment and load configuration
    initialize_environment
    
    if ! load_config; then
        exit 1
    fi
    
    # Export configuration for other modules
    export_config
    
    # Log start with configuration info
    log "INFO" "Starting YouMAD? v2.4"
    [[ "$DRY_RUN" == true ]] && log "INFO" "Dry run mode enabled"
    [[ "$OVERRIDE" == true ]] && log "INFO" "Override mode enabled"
    [[ "$VERBOSE" == true ]] && log "INFO" "Verbose mode enabled"
    
    # Initialize files
    initialize_files
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Process URLs
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
