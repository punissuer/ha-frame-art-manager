#!/usr/bin/with-contenv bashio

# Get options from add-on configuration
FRAME_ART_PATH=$(bashio::config 'frame_art_path')
PORT=$(bashio::config 'port')
HOME_NAME=$(bashio::config 'home')

# Log configuration
bashio::log.info "Starting Frame Art Manager..."
bashio::log.info "Frame Art Path: ${FRAME_ART_PATH}"
bashio::log.info "Port: ${PORT}"
if bashio::var.is_empty "${HOME_NAME}"; then
    bashio::log.info "Home: (not set)"
else
    bashio::log.info "Home: ${HOME_NAME}"
fi

# Verify that the Home Assistant config share is mounted when using /config paths
if [[ "${FRAME_ART_PATH}" == /config/* ]] && [ ! -d "/config/.storage" ]; then
    bashio::log.error "Home Assistant /config share is not mounted. Check add-on map configuration."
    bashio::exit.nok "Cannot proceed without access to /config"
fi

# Ensure the frame art directory exists and is accessible
if [ ! -d "${FRAME_ART_PATH}" ]; then
    bashio::log.info "Creating frame art directory: ${FRAME_ART_PATH}"
    mkdir -p "${FRAME_ART_PATH}"
fi

# Export environment variables for Node.js app
export FRAME_ART_PATH="${FRAME_ART_PATH}"
export PORT="${PORT}"
export FRAME_ART_HOME="${HOME_NAME}"
export NODE_ENV="production"

# Change to app directory
cd /app || bashio::exit.nok "Could not change to app directory"

# Start the application
bashio::log.info "Starting Node.js server..."
export SYNC_ENABLED=false
exec node server.js
