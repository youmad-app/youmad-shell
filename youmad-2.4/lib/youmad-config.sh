#!/bin/bash
# YouMAD? - Configuration Management Module v2.4
# Handles all configuration loading, validation, and environment setup

# Default configuration values
readonly DEFAULT_LIMIT_RATE="4M"
readonly DEFAULT_BROWSER="chrome"
readonly DEFAULT_MAX_LOG_LINES=5000
readonly DEFAULT_ROTATION_KEEP=3

# Configuration variables (will be set by load_config)
LIMIT_RATE=""
BROWSER=""
MAX_LOG_LINES=""
ROTATION_KEEP=""

# Initialize configuration from environment variables and config file
initialize_environment() {
    # Set up work directory
    WORK_DIR="${YOUMAD_WORK_DIR:-$HOME/youmad}"
    CONFIG_FILE="$WORK_DIR/config"
    mkdir -p "$WORK_DIR"

    # Set up file paths
    URL_FILE="${YOUMAD_URL_FILE:-./urls.txt}"
    DOWNLOAD_ARCHIVE="$WORK_DIR/downloaded.txt"
    ERROR_LOG="$WORK_DIR/errors.log"
    ACTIVITY_LOG="$WORK_DIR/activity.log"
    
    # User agent for web requests
    USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

# Load configuration from environment variables and config file
load_config() {
    [[ "$VERBOSE" == true ]] && log "INFO" "Loading configuration..."
    
    # Check if config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
        if source "$CONFIG_FILE" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Loaded configuration from $CONFIG_FILE"
        else
            log "ERROR" "Configuration file corrupted: $CONFIG_FILE"
            log "INFO" "Recreating configuration..."
            create_interactive_config
            return $?
        fi
    else
        log "INFO" "Configuration file not found. Initializing..."
        create_interactive_config
        return $?
    fi
    
    # Apply environment variable overrides (Docker-friendly)
    LIMIT_RATE="${YOUMAD_LIMIT_RATE:-${LIMIT_RATE:-$DEFAULT_LIMIT_RATE}}"
    BROWSER="${YOUMAD_BROWSER:-${BROWSER:-$DEFAULT_BROWSER}}"
    MAX_LOG_LINES="${YOUMAD_MAX_LOG_LINES:-${MAX_LOG_LINES:-$DEFAULT_MAX_LOG_LINES}}"
    ROTATION_KEEP="${YOUMAD_ROTATION_KEEP:-${ROTATION_KEEP:-$DEFAULT_ROTATION_KEEP}}"
    
    # Validate configuration
    if ! validate_config; then
        log "ERROR" "Configuration validation failed"
        return 1
    fi
    
    log "INFO" "Configuration loaded: $LIMIT_RATE, $BROWSER"
    return 0
}

# Create interactive configuration (for --config flag)
create_interactive_config() {
    log "INFO" "Creating configuration at $CONFIG_FILE..."

    echo "=== YouMAD? Configuration ==="
    echo "Leave blank to use defaults shown in brackets."
    echo

    # Get download rate
    local input_limit
    read -rp "Maximum download rate (e.g., 4M, 1M, 500K) [${DEFAULT_LIMIT_RATE}]: " input_limit
    LIMIT_RATE="${input_limit:-$DEFAULT_LIMIT_RATE}"

    # Get browser
    local input_browser
    read -rp "Browser for cookies (chrome, chromium, brave, firefox, safari, edge) [${DEFAULT_BROWSER}]: " input_browser
    BROWSER="${input_browser:-$DEFAULT_BROWSER}"

    # Advanced options (optional)
    echo
    echo "Advanced options (press Enter for defaults):"
    
    local input_max_log
    read -rp "Maximum log lines before rotation [${DEFAULT_MAX_LOG_LINES}]: " input_max_log
    MAX_LOG_LINES="${input_max_log:-$DEFAULT_MAX_LOG_LINES}"
    
    local input_rotation
    read -rp "Number of rotated logs to keep [${DEFAULT_ROTATION_KEEP}]: " input_rotation
    ROTATION_KEEP="${input_rotation:-$DEFAULT_ROTATION_KEEP}"

    # Validate configuration before saving
    if ! validate_config; then
        log "ERROR" "Invalid configuration values entered"
        return 1
    fi

    # Save configuration
    save_config
    log "INFO" "Configuration saved to $CONFIG_FILE"
    return 0
}

# Save current configuration to file
save_config() {
    cat > "$CONFIG_FILE" <<EOF
# YouMAD? Configuration v2.4
# Generated on $(date)

# Download settings
LIMIT_RATE=$LIMIT_RATE
BROWSER=$BROWSER

# Log management
MAX_LOG_LINES=$MAX_LOG_LINES
ROTATION_KEEP=$ROTATION_KEEP

# Environment variable overrides:
# YOUMAD_LIMIT_RATE - Override download rate limit
# YOUMAD_BROWSER - Override browser for cookies
# YOUMAD_WORK_DIR - Override working directory
# YOUMAD_URL_FILE - Override URL file location
# YOUMAD_MAX_LOG_LINES - Override log rotation threshold
# YOUMAD_ROTATION_KEEP - Override number of rotated logs to keep
EOF
}

# Validate configuration values
validate_config() {
    local errors=0
    
    # Validate download rate
    if ! validate_download_rate "$LIMIT_RATE"; then
        log "ERROR" "Invalid download rate: $LIMIT_RATE"
        log "INFO" "Valid formats: 1M, 500K, 2.5M, 1000K"
        ((errors++))
    fi
    
    # Validate browser
    if ! validate_browser "$BROWSER"; then
        log "ERROR" "Invalid browser: $BROWSER"
        log "INFO" "Valid browsers: chrome, chromium, brave, firefox, safari, edge"
        ((errors++))
    fi
    
    # Validate log settings
    if ! validate_positive_integer "$MAX_LOG_LINES" "MAX_LOG_LINES"; then
        ((errors++))
    fi
    
    if ! validate_positive_integer "$ROTATION_KEEP" "ROTATION_KEEP"; then
        ((errors++))
    fi
    
    return $errors
}

# Validate download rate format
validate_download_rate() {
    local rate="$1"
    # Accept formats like: 1M, 500K, 2.5M, 1000K, 50m, 100k
    if [[ "$rate" =~ ^[0-9]+(\.[0-9]+)?[KkMm]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate browser name
validate_browser() {
    local browser="$1"
    case "$browser" in
        chrome|chromium|brave|firefox|safari|edge)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate positive integer
validate_positive_integer() {
    local value="$1"
    local name="$2"
    
    if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
        return 0
    else
        log "ERROR" "Invalid $name: $value (must be positive integer)"
        return 1
    fi
}

# Show current configuration
show_config() {
    echo "=== Current YouMAD? Configuration ==="
    echo "Download rate limit: $LIMIT_RATE"
    echo "Browser for cookies: $BROWSER"
    echo "Maximum log lines: $MAX_LOG_LINES"
    echo "Rotated logs to keep: $ROTATION_KEEP"
    echo "Working directory: $WORK_DIR"
    echo "URL file: $URL_FILE"
    echo "Activity log: $ACTIVITY_LOG"
    echo
    echo "Configuration file: $CONFIG_FILE"
    echo "Environment overrides available:"
    echo "  YOUMAD_LIMIT_RATE=$YOUMAD_LIMIT_RATE"
    echo "  YOUMAD_BROWSER=$YOUMAD_BROWSER"
    echo "  YOUMAD_WORK_DIR=$YOUMAD_WORK_DIR"
    echo "  YOUMAD_URL_FILE=$YOUMAD_URL_FILE"
}

# Export configuration for use by other modules
export_config() {
    # Export core settings
    export LIMIT_RATE BROWSER MAX_LOG_LINES ROTATION_KEEP
    export WORK_DIR CONFIG_FILE URL_FILE DOWNLOAD_ARCHIVE ERROR_LOG ACTIVITY_LOG USER_AGENT
    
    # Export derived settings
    export YOUMAD_CONFIG_LOADED=true
}

# Initialize Docker-friendly defaults
init_docker_config() {
    # Set Docker-friendly defaults
    WORK_DIR="${YOUMAD_WORK_DIR:-/app/data}"
    URL_FILE="${YOUMAD_URL_FILE:-/app/urls.txt}"
    LIMIT_RATE="${YOUMAD_LIMIT_RATE:-$DEFAULT_LIMIT_RATE}"
    BROWSER="${YOUMAD_BROWSER:-$DEFAULT_BROWSER}"
    MAX_LOG_LINES="${YOUMAD_MAX_LOG_LINES:-$DEFAULT_MAX_LOG_LINES}"
    ROTATION_KEEP="${YOUMAD_ROTATION_KEEP:-$DEFAULT_ROTATION_KEEP}"
    
    # Ensure directories exist
    mkdir -p "$WORK_DIR"
    mkdir -p "$(dirname "$URL_FILE")"
    
    # Set file paths
    CONFIG_FILE="$WORK_DIR/config"
    DOWNLOAD_ARCHIVE="$WORK_DIR/downloaded.txt"
    ERROR_LOG="$WORK_DIR/errors.log"
    ACTIVITY_LOG="$WORK_DIR/activity.log"
    
    # Validate Docker configuration
    if ! validate_config; then
        log "ERROR" "Invalid Docker configuration"
        return 1
    fi
    
    # Save configuration for persistence
    save_config
    export_config
    
    log "INFO" "Docker configuration initialized"
    return 0
}

# Reset configuration to defaults
reset_config() {
    LIMIT_RATE="$DEFAULT_LIMIT_RATE"
    BROWSER="$DEFAULT_BROWSER"
    MAX_LOG_LINES="$DEFAULT_MAX_LOG_LINES"
    ROTATION_KEEP="$DEFAULT_ROTATION_KEEP"
    
    save_config
    log "INFO" "Configuration reset to defaults"
}
