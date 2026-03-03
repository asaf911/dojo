#!/bin/bash

# Exit on any error
set -e

# Destination path for the copied GoogleService-Info.plist file in the app bundle
CONFIG_EXTENSION_OUTPUT_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"

# Check if GOOGLE_SERVICE_CONFIG_PLIST is set and the file exists
if [ -z "${GOOGLE_SERVICE_CONFIG_PLIST}" ]; then
    echo "Error: GOOGLE_SERVICE_CONFIG_PLIST is not set"
    exit 1
fi

if [ ! -f "${GOOGLE_SERVICE_CONFIG_PLIST}" ]; then
    echo "Error: GoogleService-Info.plist file not found at: ${GOOGLE_SERVICE_CONFIG_PLIST}"
    exit 1
fi

# Remove the existing GoogleService-Info.plist file if it exists in the app bundle
# (otherwise there might be permission issues when trying to copy it over again)
if [ -f "${CONFIG_EXTENSION_OUTPUT_PATH}" ]; then
    rm "${CONFIG_EXTENSION_OUTPUT_PATH}"
fi

# Copy the GoogleService-Info.plist file
cp -p "${GOOGLE_SERVICE_CONFIG_PLIST}" "${CONFIG_EXTENSION_OUTPUT_PATH}"

echo "Successfully copied GoogleService-Info.plist from ${GOOGLE_SERVICE_CONFIG_PLIST} to ${CONFIG_EXTENSION_OUTPUT_PATH}"
