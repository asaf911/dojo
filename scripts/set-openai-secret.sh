#!/bin/bash
# Set OPENAI_API_KEY in Firebase Secret Manager
# Requires: firebase CLI (npm install -g firebase-tools) and fix npm permissions if needed:
#   sudo chown -R $(whoami) ~/.npm
#
# Run: echo -n "YOUR_KEY" | firebase functions:secrets:set OPENAI_API_KEY --data-file=-
# Or:  firebase functions:secrets:set OPENAI_API_KEY  (then paste when prompted)
#
# Alternative: Use Google Cloud Console → Security → Secret Manager → Create Secret
