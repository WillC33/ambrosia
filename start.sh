#!/bin/sh

# Check if user provided content, otherwise use sample
if [ ! -f "/app/gemini/index.gmi" ] && [ -z "$(find /app/gemini -name "*.gmi" 2>/dev/null | head -1)" ]; then
    echo "No .gmi content found, using sample content"
    export ROOT_DIR=/app/gemini-sample
else
    echo "Using user content from /app/gemini"
    export ROOT_DIR=/app/gemini
fi

# Generate cert if missing
if [ ! -f "/certs/cert.pem" ]; then
    mkdir -p /tmp/certs
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /tmp/certs/key.pem \
        -out /tmp/certs/cert.pem \
        -days 365 -subj "/CN=${HOSTNAME:-localhost}"
    export CERT_FILE=/tmp/certs/cert.pem
    export KEY_FILE=/tmp/certs/key.pem
else
    export CERT_FILE=/certs/cert.pem
    export KEY_FILE=/certs/key.pem
fi

# Start server
exec /app/bin/ambrosia start
