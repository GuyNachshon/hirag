#!/bin/bash
set -e

# Export Airgapped Deployment Package
# Exports all Docker images to tar.gz with chunking for large files
# Usage: ./export-airgapped-package.sh [OUTPUT_DIR] [VERSION]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_DIR=${1:-"/tmp/rag-deployment"}
VERSION=${2:-"1.0.0"}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PACKAGE_NAME="rag-system-deployment_v${VERSION}_${TIMESTAMP}"
PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"
CHUNK_SIZE_GB=10

# Images to export
IMAGES=(
    "rag-frontend:latest"
    "rag-api:latest"
    "rag-whisper:latest"
    "rag-llm:latest"
    "rag-dots-ocr:latest"
)

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Exporting Airgapped Deployment Package${NC}"
echo -e "${BLUE}  Version: ${VERSION}${NC}"
echo -e "${BLUE}  Output: ${PACKAGE_DIR}${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Create package directory structure
echo -e "${YELLOW}Creating package directory structure...${NC}"
mkdir -p "${PACKAGE_DIR}"/{images,configs,scripts,docs}
echo -e "${GREEN}✓ Directory structure created${NC}"
echo ""

# Export each image
echo -e "${BLUE}Exporting Docker images...${NC}"
echo ""

TOTAL_SIZE=0
EXPORT_STATS=()

for image in "${IMAGES[@]}"; do
    image_name=$(echo "$image" | cut -d':' -f1)
    image_tag=$(echo "$image" | cut -d':' -f2)
    safe_name=$(echo "$image_name" | sed 's/\//-/g')
    tar_file="${PACKAGE_DIR}/images/${safe_name}_${image_tag}.tar"

    echo -e "${YELLOW}Exporting ${image}...${NC}"

    # Check if image exists
    if ! docker image inspect "$image" &> /dev/null; then
        echo -e "${RED}✗ Image not found: ${image}${NC}"
        echo -e "${RED}  Run build-all-complete.sh first${NC}"
        exit 1
    fi

    # Export image to tar
    echo "  Creating tar archive..."
    if docker save "$image" -o "$tar_file"; then
        # Get size in bytes
        size_bytes=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null)
        size_mb=$((size_bytes / 1024 / 1024))
        size_gb=$((size_mb / 1024))
        TOTAL_SIZE=$((TOTAL_SIZE + size_bytes))

        echo -e "${GREEN}  ✓ Exported: ${size_mb} MB${NC}"

        # Compress
        echo "  Compressing..."
        if gzip -f "$tar_file"; then
            compressed_size=$(stat -f%z "${tar_file}.gz" 2>/dev/null || stat -c%s "${tar_file}.gz" 2>/dev/null)
            compressed_mb=$((compressed_size / 1024 / 1024))
            echo -e "${GREEN}  ✓ Compressed: ${compressed_mb} MB${NC}"

            # Check if chunking is needed
            if [ $size_gb -ge $CHUNK_SIZE_GB ]; then
                echo "  File size exceeds ${CHUNK_SIZE_GB}GB, chunking..."
                chunk_size=$((CHUNK_SIZE_GB * 1024 * 1024 * 1024))
                split -b ${chunk_size} "${tar_file}.gz" "${tar_file}.gz.part_"
                rm "${tar_file}.gz"

                chunk_count=$(ls -1 "${tar_file}.gz.part_"* 2>/dev/null | wc -l)
                echo -e "${GREEN}  ✓ Split into ${chunk_count} chunks${NC}"
                EXPORT_STATS+=("${image}|${size_mb}MB|${compressed_mb}MB|${chunk_count} chunks")
            else
                echo -e "${GREEN}  ✓ No chunking needed${NC}"
                EXPORT_STATS+=("${image}|${size_mb}MB|${compressed_mb}MB|1 file")
            fi
        else
            echo -e "${RED}  ✗ Compression failed${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗ Export failed for ${image}${NC}"
        exit 1
    fi
    echo ""
done

# Generate checksums
echo -e "${YELLOW}Generating checksums...${NC}"
cd "${PACKAGE_DIR}/images"
sha256sum * > checksums.sha256
echo -e "${GREEN}✓ Checksums generated${NC}"
cd - > /dev/null
echo ""

# Copy configuration files
echo -e "${YELLOW}Copying configuration files...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Copy docker-compose and configs
if [ -f "${PROJECT_ROOT}/docker-compose.yml" ]; then
    cp "${PROJECT_ROOT}/docker-compose.yml" "${PACKAGE_DIR}/configs/"
    echo -e "${GREEN}  ✓ Copied docker-compose.yml${NC}"
fi

if [ -d "${PROJECT_ROOT}/configs" ]; then
    cp -r "${PROJECT_ROOT}/configs/"* "${PACKAGE_DIR}/configs/" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Copied config files${NC}"
fi

if [ -f "${PROJECT_ROOT}/HiRAG/config.yaml" ]; then
    cp "${PROJECT_ROOT}/HiRAG/config.yaml" "${PACKAGE_DIR}/configs/hirag-config.yaml"
    echo -e "${GREEN}  ✓ Copied HiRAG config${NC}"
fi
echo ""

# Generate manifest
echo -e "${YELLOW}Generating manifest...${NC}"
cat > "${PACKAGE_DIR}/manifest.json" <<EOF
{
  "version": "${VERSION}",
  "timestamp": "${TIMESTAMP}",
  "package_name": "${PACKAGE_NAME}",
  "images": [
$(for i in "${!IMAGES[@]}"; do
    echo "    \"${IMAGES[$i]}\""
    [ $i -lt $((${#IMAGES[@]} - 1)) ] && echo "," || echo ""
done)
  ],
  "total_size_bytes": ${TOTAL_SIZE},
  "total_size_gb": $((TOTAL_SIZE / 1024 / 1024 / 1024)),
  "exported_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "system_requirements": {
    "min_ram_gb": 32,
    "min_disk_gb": 200,
    "recommended_ram_gb": 64,
    "recommended_disk_gb": 500,
    "gpu_required": true,
    "min_gpu_vram_gb": 24
  },
  "services": [
    {"name": "frontend", "port": 8087, "image": "rag-frontend:latest"},
    {"name": "api", "port": 8080, "image": "rag-api:latest"},
    {"name": "whisper", "port": 8004, "image": "rag-whisper:latest"},
    {"name": "llm", "port": 8000, "image": "rag-llm:latest"},
    {"name": "dots-ocr", "port": 8002, "image": "rag-dots-ocr:latest"}
  ]
}
EOF
echo -e "${GREEN}✓ Manifest generated${NC}"
echo ""

# Create README
echo -e "${YELLOW}Creating package README...${NC}"
cat > "${PACKAGE_DIR}/README.md" <<'EOF'
# RAG System Airgapped Deployment Package

This package contains all Docker images and configurations needed to deploy the RAG system in an airgapped environment.

## Contents

- `images/` - Docker images (tar.gz format, some chunked)
- `configs/` - Configuration files
- `scripts/` - Deployment scripts
- `docs/` - Documentation
- `manifest.json` - Package metadata
- `README.md` - This file

## Quick Start

### 1. Verify Package Integrity

```bash
cd images/
sha256sum -c checksums.sha256
```

### 2. Import Docker Images

If images are chunked, reassemble first:
```bash
cat rag-llm_latest.tar.gz.part_* > rag-llm_latest.tar.gz
```

Import all images:
```bash
cd ../scripts
./import-images.sh
```

### 3. Deploy Services

```bash
./deploy.sh
```

### 4. Verify Deployment

```bash
docker ps
curl http://localhost:8080/health
```

## System Requirements

- **Minimum:**
  - RAM: 32GB
  - Disk: 200GB
  - GPU: 24GB VRAM

- **Recommended:**
  - RAM: 64GB+
  - Disk: 500GB+
  - GPU: 48GB+ VRAM (H100/A100)

## Documentation

See `docs/` directory for comprehensive guides:
- `QUICK_START.md` - 5-minute deployment
- `DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `OPS_GUIDE.md` - Operations and maintenance
- `AIRGAPPED.md` - Airgapped deployment procedures

## Support

For issues, see `docs/OPS_GUIDE.md` troubleshooting section.
EOF
echo -e "${GREEN}✓ README created${NC}"
echo ""

# Create import script (will be enhanced later)
echo -e "${YELLOW}Creating import script...${NC}"
cat > "${PACKAGE_DIR}/scripts/import-images.sh" <<'SCRIPT_EOF'
#!/bin/bash
set -e

# Import Docker Images
# This script imports all Docker images from the package

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Importing Docker images...${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="$(cd "$SCRIPT_DIR/../images" && pwd)"

cd "$IMAGES_DIR"

# Reassemble chunked files
echo -e "${YELLOW}Checking for chunked files...${NC}"
for part_file in *.part_aa; do
    if [ -f "$part_file" ]; then
        base_name=$(echo "$part_file" | sed 's/.part_aa$//')
        echo "  Reassembling ${base_name}..."
        cat "${base_name}.part_"* > "$base_name"
        rm "${base_name}.part_"*
        echo -e "${GREEN}  ✓ Reassembled${NC}"
    fi
done
echo ""

# Import each image
for gz_file in *.tar.gz; do
    if [ -f "$gz_file" ]; then
        echo -e "${YELLOW}Importing ${gz_file}...${NC}"

        # Decompress
        gunzip -c "$gz_file" | docker load

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Imported successfully${NC}"
        else
            echo -e "${RED}✗ Import failed${NC}"
            exit 1
        fi
        echo ""
    fi
done

echo -e "${GREEN}All images imported successfully!${NC}"
echo ""
echo "Available images:"
docker images | grep -E "rag-(frontend|api|whisper|llm|dots-ocr)"
SCRIPT_EOF
chmod +x "${PACKAGE_DIR}/scripts/import-images.sh"
echo -e "${GREEN}✓ Import script created${NC}"
echo ""

# Summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Export Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

total_gb=$((TOTAL_SIZE / 1024 / 1024 / 1024))
echo -e "${GREEN}Package: ${PACKAGE_NAME}${NC}"
echo -e "${GREEN}Location: ${PACKAGE_DIR}${NC}"
echo -e "${GREEN}Total size: ${total_gb} GB (${TOTAL_SIZE} bytes)${NC}"
echo ""

echo -e "${BLUE}Exported images:${NC}"
for stat in "${EXPORT_STATS[@]}"; do
    IFS='|' read -r image size compressed chunks <<< "$stat"
    echo "  ${image}"
    echo "    Original: ${size}, Compressed: ${compressed}, ${chunks}"
done
echo ""

echo -e "${GREEN}✓ Export complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Verify checksums: cd ${PACKAGE_DIR}/images && sha256sum -c checksums.sha256"
echo "  2. Upload to GCP: ./upload-to-gcp.sh ${PACKAGE_DIR}"
echo "  3. Or transfer to target system: rsync -avz ${PACKAGE_DIR} user@host:/destination/"
echo ""
