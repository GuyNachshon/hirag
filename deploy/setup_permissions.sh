#!/bin/bash

echo "Setting up permissions for deployment scripts..."

# Make all shell scripts executable
chmod +x *.sh

# Create data directory structure
mkdir -p data/{input,working,logs,cache}
mkdir -p config

echo "✓ All scripts are now executable"
echo "✓ Data directory structure created"
echo ""
echo "Available scripts:"
ls -la *.sh