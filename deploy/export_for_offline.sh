#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Exporting RAG system Docker images for offline transfer"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Create export directory
EXPORT_DIR="./rag-system-export"
mkdir -p "$EXPORT_DIR"

print_status "Export directory: $EXPORT_DIR"

# List of images to export
IMAGES=(
    "rag-dots-ocr:latest"
    "rag-embedding-server:latest"
    "rag-llm-small:latest"
    "rag-llm-gptoss:latest"
    "rag-whisper:latest"
    "rag-api:latest"
    "rag-frontend:latest"
)

# Export each image
for image in "${IMAGES[@]}"; do
    print_status "Exporting $image..."
    
    # Create filename from image name
    filename=$(echo "$image" | tr ':' '_' | tr '/' '_')
    output_file="$EXPORT_DIR/${filename}.tar"
    
    if docker save -o "$output_file" "$image"; then
        # Get file size for verification
        size=$(du -h "$output_file" | cut -f1)
        print_status "✓ Exported $image -> ${filename}.tar ($size)"
    else
        print_status "✗ Failed to export $image"
        exit 1
    fi
done

# Create import script for target system
cat > "$EXPORT_DIR/import_images.sh" << 'EOF'
#!/bin/bash

set -e

echo "Importing RAG system Docker images..."

GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Import all tar files
for tar_file in *.tar; do
    if [[ -f "$tar_file" ]]; then
        print_status "Importing $tar_file..."
        docker load -i "$tar_file"
        print_status "✓ Imported $tar_file"
    fi
done

print_status "All images imported successfully!"
print_status "Run 'docker images' to see imported images"
EOF

chmod +x "$EXPORT_DIR/import_images.sh"

# Create manifest file
cat > "$EXPORT_DIR/MANIFEST.txt" << EOF
RAG System Docker Images Export
Generated: $(date)
System: $(uname -a)

Exported Images:
EOF

for image in "${IMAGES[@]}"; do
    echo "  - $image" >> "$EXPORT_DIR/MANIFEST.txt"
done

cat >> "$EXPORT_DIR/MANIFEST.txt" << EOF

Files in this directory:
EOF

ls -lh "$EXPORT_DIR" >> "$EXPORT_DIR/MANIFEST.txt"

# Calculate total size
total_size=$(du -sh "$EXPORT_DIR" | cut -f1)

print_status "=========================================="
print_status "Export complete!"
print_status "=========================================="
print_status "Export directory: $EXPORT_DIR"
print_status "Total size: $total_size"
print_status ""
print_status "To transfer to target system:"
print_status "1. Copy the entire '$EXPORT_DIR' directory"
print_status "2. On target system, run: cd $EXPORT_DIR && ./import_images.sh"
print_status ""
print_status "Files created:"
ls -la "$EXPORT_DIR"