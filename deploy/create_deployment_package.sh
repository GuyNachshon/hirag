#!/bin/bash

set -e  # Exit on any error

# Configuration
PACKAGE_NAME="rag-system-deployment"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_VERSION="v1.0.0"
PACKAGE_DIR="${PACKAGE_NAME}_${PACKAGE_VERSION}_${TIMESTAMP}"
GCP_BUCKET="${GCP_BUCKET:-gs://baddon-ai-deployment}"  # Default bucket, can be overridden

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check Docker
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check gcloud auth
    if ! gcloud auth list --format="value(account)" | grep -q "@"; then
        print_error "Not authenticated with gcloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check gsutil
    if ! command -v gsutil &> /dev/null; then
        print_error "gsutil not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Display current auth status
    print_status "Authenticated accounts:"
    gcloud auth list --format="table(account,status)" | grep -v "^ACCOUNT"
    
    print_status "Using GCP bucket: $GCP_BUCKET"
    echo ""
}

# Function to ensure GCP bucket exists
ensure_bucket_exists() {
    print_step "Checking GCP bucket..."
    
    local bucket_name=$(echo "$GCP_BUCKET" | sed 's/gs:\/\///')
    
    # Check if bucket exists
    if gsutil ls -b "$GCP_BUCKET" > /dev/null 2>&1; then
        print_status "✓ Bucket exists: $GCP_BUCKET"
    else
        print_status "Bucket does not exist, creating: $GCP_BUCKET"
        
        # Get current project
        local project_id=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$project_id" ]; then
            print_error "No GCP project set. Please run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
        
        # Create bucket with default settings
        if gsutil mb -p "$project_id" "$GCP_BUCKET"; then
            print_status "✓ Successfully created bucket: $GCP_BUCKET"
            
            # Set appropriate lifecycle policy to manage costs
            cat > /tmp/lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {
        "age": 90,
        "matchesStorageClass": ["STANDARD", "NEARLINE", "COLDLINE"]
      }
    }
  ]
}
EOF
            gsutil lifecycle set /tmp/lifecycle.json "$GCP_BUCKET" && \
            print_status "✓ Set lifecycle policy (90 day retention)"
            rm /tmp/lifecycle.json
            
        else
            print_error "Failed to create bucket. Please create it manually:"
            print_error "  gsutil mb -p $project_id $GCP_BUCKET"
            exit 1
        fi
    fi
    
    # Test write permissions
    echo "test" | gsutil cp - "$GCP_BUCKET/test-write-permission.txt" > /dev/null 2>&1
    if gsutil rm "$GCP_BUCKET/test-write-permission.txt" > /dev/null 2>&1; then
        print_status "✓ Write permissions confirmed"
    else
        print_error "No write permissions to bucket: $GCP_BUCKET"
        exit 1
    fi
    
    echo ""
}

# Function to build all images
build_all_images() {
    print_step "Building all Docker images with optimizations..."
    
    # Get script directory and parent directory
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    
    cd "$PARENT_DIR"
    
    # Run the build script
    if ! ./deploy/build_all_offline.sh; then
        print_error "Failed to build Docker images"
        exit 1
    fi
    
    print_status "✓ All Docker images built successfully"
    echo ""
}

# Function to find existing incomplete package
find_incomplete_package() {
    local pattern="${PACKAGE_NAME}_${PACKAGE_VERSION}_*"
    local existing_dirs=($(ls -d $pattern 2>/dev/null | head -1))
    
    if [[ ${#existing_dirs[@]} -gt 0 ]]; then
        local existing_dir="${existing_dirs[0]}"
        if [[ -d "$existing_dir" && -d "$existing_dir/images" ]]; then
            # Check if package is incomplete (no final tar.gz)
            if [[ ! -f "${existing_dir}.tar.gz" ]]; then
                echo "$existing_dir"
                return 0
            fi
        fi
    fi
    
    echo ""
    return 1
}

# Function to create deployment package directory structure
create_package_structure() {
    print_step "Creating deployment package structure..."
    
    # Check for existing incomplete package
    local incomplete_package=$(find_incomplete_package)
    
    if [[ -n "$incomplete_package" ]]; then
        print_warning "Found incomplete package: $incomplete_package"
        echo -n "Resume existing package? [y/N]: "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            PACKAGE_DIR="$incomplete_package"
            print_status "✓ Resuming existing package: $PACKAGE_DIR"
            
            # Ensure all subdirectories exist
            mkdir -p "$PACKAGE_DIR/images"
            mkdir -p "$PACKAGE_DIR/docs"
            mkdir -p "$PACKAGE_DIR/scripts" 
            mkdir -p "$PACKAGE_DIR/config"
            
            return 0
        else
            print_status "Creating new package..."
            # Clean up existing incomplete package
            rm -rf "$incomplete_package"
        fi
    fi
    
    # Clean up any existing package with same name
    rm -rf "$PACKAGE_DIR"
    rm -f "${PACKAGE_DIR}.tar.gz"
    
    # Create main package directory
    mkdir -p "$PACKAGE_DIR"
    
    # Create subdirectories
    mkdir -p "$PACKAGE_DIR/images"
    mkdir -p "$PACKAGE_DIR/docs"
    mkdir -p "$PACKAGE_DIR/scripts"
    mkdir -p "$PACKAGE_DIR/config"
    
    print_status "✓ Package structure created: $PACKAGE_DIR"
}

# Function to export and upload Docker images
export_and_upload_images() {
    print_step "Exporting and uploading Docker images to GCS..."
    
    local images=(
        "rag-frontend:latest"
        "rag-api:optimized"
        "rag-llm-gptoss:latest"
        "rag-embedding-server:tgi-optimized"
        "rag-dots-ocr:latest"
        "rag-whisper:latest"
    )
    
    cd "$PACKAGE_DIR/images"
    
    for image in "${images[@]}"; do
        local safe_name=$(echo "$image" | sed 's/:/_/g' | sed 's/\//_/g')
        local tar_file="${safe_name}.tar"
        local compressed_file="${safe_name}.tar.gz"
        
        print_status "Processing $image..."
        
        # Check if already uploaded to GCS
        if gsutil ls "$GCP_BUCKET/$compressed_file" >/dev/null 2>&1; then
            print_status "✓ $image already uploaded to GCS"
            continue
        fi
        
        # Check if we can reuse existing export
        local existing_export=""
        for existing_dir in ../rag-system-deployment_v1.0.0_*/images/; do
            if [[ -f "${existing_dir}${tar_file}" && -s "${existing_dir}${tar_file}" ]]; then
                existing_export="${existing_dir}${tar_file}"
                break
            fi
        done
        
        if [[ -n "$existing_export" ]]; then
            local existing_size=$(du -sh "$existing_export" | cut -f1)
            print_status "  ♻️ Reusing existing export: $existing_export ($existing_size)"
            cp "$existing_export" "$tar_file"
        else
            # Remove any incomplete local files
            rm -f "$tar_file" "$compressed_file" "${tar_file}.tmp" ".tmp-${tar_file}"*
            
            # Export Docker image
            print_status "  Exporting $image -> $tar_file"
            if ! docker save "$image" -o "$tar_file"; then
                print_error "✗ Failed to export $image"
                exit 1
            fi
        fi
        
        local tar_size=$(du -sh "$tar_file" | cut -f1)
        print_status "  ✓ Exported ($tar_size)"
        
        # Compress the tar file
        print_status "  Compressing $tar_file -> $compressed_file"
        if gzip "$tar_file"; then
            local compressed_size=$(du -sh "$compressed_file" | cut -f1)
            print_status "  ✓ Compressed ($compressed_size)"
        else
            print_error "✗ Failed to compress $tar_file"
            exit 1
        fi
        
        # Upload to GCS
        print_status "  Uploading $compressed_file to GCS..."
        if gsutil -m cp "$compressed_file" "$GCP_BUCKET/"; then
            print_status "  ✓ Uploaded $compressed_file"
            
            # Set metadata
            gsutil setmeta \
                -h "x-goog-meta-image:$image" \
                -h "x-goog-meta-version:$PACKAGE_VERSION" \
                -h "x-goog-meta-created:$(date -Iseconds)" \
                "$GCP_BUCKET/$compressed_file"
            
            # Clean up local files after successful upload
            rm -f "$compressed_file"
        else
            print_error "✗ Failed to upload $compressed_file"
            exit 1
        fi
        
        print_status "✓ $image completed"
        echo ""
    done
    
    # Create image manifest
    cat > "MANIFEST.md" << EOF
# Docker Images Manifest

**Package:** $PACKAGE_NAME $PACKAGE_VERSION
**Created:** $(date)
**Total Images:** ${#images[@]}

## Images Included

| Service | Image | File | Purpose |
|---------|-------|------|---------|
| Frontend | rag-frontend:latest | rag-frontend_latest.tar | Vue.js web interface |
| API | rag-api:optimized | rag-api_optimized.tar | FastAPI backend with HiRAG (optimized: ~1.6GB) |
| LLM GPT-OSS | rag-llm-gptoss:latest | rag-llm-gptoss_latest.tar | Large language model (20B params) |
| Embedding | rag-embedding-server:tgi-optimized | rag-embedding-server_tgi-optimized.tar | Text embedding service (TGI: ~17GB) |
| DotsOCR | rag-dots-ocr:optimized | rag-dots-ocr_optimized.tar | Vision-language OCR (optimized) |
| Whisper | rag-whisper:latest | rag-whisper_latest.tar | Hebrew transcription |

## Import Instructions

Run the following commands on the target system:

\`\`\`bash
# Load all images
for tar_file in *.tar; do
    echo "Loading \$tar_file..."
    docker load -i "\$tar_file"
done

# Verify images loaded
docker images | grep rag-
\`\`\`
EOF
    
    cd ../..
    print_status "✓ All images exported with manifest"
    echo ""
}

# Function to copy deployment scripts
copy_deployment_scripts() {
    print_step "Copying deployment scripts and configurations..."
    
    # Copy essential deployment scripts
    cp deploy/deploy_complete.sh "$PACKAGE_DIR/scripts/"
    cp deploy/validate_offline_deployment.sh "$PACKAGE_DIR/scripts/"
    cp deploy/test_services_sequential.sh "$PACKAGE_DIR/scripts/"
    cp deploy/test_service_functions.sh "$PACKAGE_DIR/scripts/"
    cp deploy/setup_network.sh "$PACKAGE_DIR/scripts/"
    
    # Copy configuration templates
    if [ -d "deploy/config" ]; then
        cp -r deploy/config/* "$PACKAGE_DIR/config/" 2>/dev/null || true
    fi
    
    # Create import script
    cat > "$PACKAGE_DIR/scripts/import_images.sh" << 'EOF'
#!/bin/bash

set -e

echo "=========================================="
echo "Importing RAG System Docker Images"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Navigate to images directory
cd "$(dirname "$0")/../images"

if [ ! -d "." ]; then
    print_error "Images directory not found!"
    exit 1
fi

# Import all tar files
for tar_file in *.tar; do
    if [ -f "$tar_file" ]; then
        print_status "Loading $tar_file..."
        if docker load -i "$tar_file"; then
            print_status "✓ Successfully loaded $tar_file"
        else
            print_error "✗ Failed to load $tar_file"
            exit 1
        fi
    fi
done

print_status ""
print_status "=========================================="
print_status "All images imported successfully!"
print_status "=========================================="

# Show imported images
print_status "Imported RAG images:"
docker images | grep -E "(rag-|REPOSITORY)" | head -10

print_status ""
print_status "Next steps:"
print_status "1. cd ../scripts"
print_status "2. ./setup_network.sh"
print_status "3. ./deploy_complete.sh"
print_status "4. ./validate_offline_deployment.sh"

EOF
    
    chmod +x "$PACKAGE_DIR/scripts/import_images.sh"
    chmod +x "$PACKAGE_DIR/scripts"/*.sh
    
    print_status "✓ Deployment scripts copied and configured"
}

# Function to copy documentation
copy_documentation() {
    print_step "Copying documentation..."
    
    # Copy key documentation files
    cp deploy/OFFLINE_DEPLOYMENT.md "$PACKAGE_DIR/docs/"
    cp deploy/SEQUENTIAL_TESTING.md "$PACKAGE_DIR/docs/"
    cp deploy/TEST_QUICK_REFERENCE.md "$PACKAGE_DIR/docs/"
    cp deploy/README.md "$PACKAGE_DIR/docs/DEPLOY_README.md"
    
    # Copy main README if it exists
    if [ -f "README.md" ]; then
        cp README.md "$PACKAGE_DIR/docs/MAIN_README.md"
    fi
    
    # Create package-specific README
    cat > "$PACKAGE_DIR/README.md" << EOF
# RAG System Deployment Package

**Version:** $PACKAGE_VERSION  
**Created:** $(date)  
**Package Size:** $(du -sh "$PACKAGE_DIR" | cut -f1) (uncompressed)

## Contents

- \`images/\` - Docker images for all RAG services ($(ls -1 "$PACKAGE_DIR/images"/*.tar | wc -l) images)
- \`scripts/\` - Deployment and testing scripts
- \`config/\` - Configuration templates
- \`docs/\` - Complete documentation

## Quick Start

### 1. Import Docker Images
\`\`\`bash
cd scripts
./import_images.sh
\`\`\`

### 2. Deploy Services
\`\`\`bash
./setup_network.sh
./deploy_complete.sh
\`\`\`

### 3. Validate Deployment
\`\`\`bash
./validate_offline_deployment.sh
\`\`\`

### 4. Sequential Testing (for GPU-constrained environments)
\`\`\`bash
./test_services_sequential.sh
\`\`\`

## System Requirements

- **Docker Engine:** 20.10+
- **GPU Memory:** 8GB+ VRAM (recommended 16GB+)
- **RAM:** 32GB+ recommended
- **Disk Space:** 100GB+ free space
- **OS:** Linux-based system (Ubuntu 20.04+ recommended)

## Documentation

See \`docs/\` directory for complete documentation:

- \`OFFLINE_DEPLOYMENT.md\` - Complete deployment guide
- \`SEQUENTIAL_TESTING.md\` - GPU memory management testing
- \`TEST_QUICK_REFERENCE.md\` - Quick testing commands

## Services Included

| Service | Purpose | Memory | Port |
|---------|---------|--------|------|
| RAG API | FastAPI backend with HiRAG | ~2GB | 8080 |
| LLM GPT-OSS | Large language model (20B) | ~16GB | 8003 |
| Embedding | Text embedding service | ~3GB | 8001 |
| DotsOCR | Vision-language OCR | ~7GB | 8002 |
| Whisper | Hebrew transcription | ~4GB | 8004 |
| Frontend | Vue.js web interface | ~100MB | 8080 |

## Support

For issues or questions, check the documentation in \`docs/\` or contact the development team.

---
*Generated by RAG System Deployment Package Creator $PACKAGE_VERSION*
EOF
    
    print_status "✓ Documentation copied and package README created"
}

# Function to upload deployment package (scripts and docs)
upload_deployment_package() {
    print_step "Creating and uploading deployment package..."
    
    # Create compressed package of scripts and docs (no images)
    local package_file="${PACKAGE_DIR}_scripts_and_docs.tar.gz"
    
    print_status "Compressing scripts and documentation..."
    tar -czf "$package_file" "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/docs" "$PACKAGE_DIR/config" "$PACKAGE_DIR/README.md" 2>/dev/null || \
    tar -czf "$package_file" --exclude="$PACKAGE_DIR/images" "$PACKAGE_DIR"
    
    local package_size=$(du -sh "$package_file" | cut -f1)
    print_status "✓ Package created: $package_file ($package_size)"
    
    # Upload to GCS
    print_status "Uploading deployment package to GCS..."
    if gsutil -m cp "$package_file" "$GCP_BUCKET/"; then
        print_status "✓ Uploaded deployment package"
        
        # Set metadata
        gsutil setmeta \
            -h "x-goog-meta-package:deployment-scripts" \
            -h "x-goog-meta-version:$PACKAGE_VERSION" \
            -h "x-goog-meta-created:$(date -Iseconds)" \
            "$GCP_BUCKET/$package_file"
        
        # Clean up
        rm -f "$package_file"
    else
        print_error "✗ Failed to upload deployment package"
        exit 1
    fi
    
    echo ""
}

# Function to create compressed package
create_compressed_package() {
    print_step "Creating compressed deployment package..."
    
    # Create tar.gz package
    print_status "Compressing package directory..."
    tar -czf "${PACKAGE_DIR}.tar.gz" "$PACKAGE_DIR"
    
    local package_size=$(du -sh "${PACKAGE_DIR}.tar.gz" | cut -f1)
    local uncompressed_size=$(du -sh "$PACKAGE_DIR" | cut -f1)
    
    print_status "✓ Package created: ${PACKAGE_DIR}.tar.gz"
    print_status "  Compressed size: $package_size"
    print_status "  Uncompressed size: $uncompressed_size"
    echo ""
}

# Function to upload to GCP bucket
upload_to_gcp() {
    print_step "Uploading deployment package to GCP bucket..."
    
    local package_file="${PACKAGE_DIR}.tar.gz"
    
    if [ ! -f "$package_file" ]; then
        print_error "Package file not found: $package_file"
        exit 1
    fi
    
    print_status "Uploading $package_file to $GCP_BUCKET..."
    
    # Upload with progress and metadata
    if gsutil -m cp "$package_file" "$GCP_BUCKET/"; then
        print_status "✓ Successfully uploaded to GCP bucket"
        
        # Set metadata
        gsutil setmeta -h "x-goog-meta-version:$PACKAGE_VERSION" \
                      -h "x-goog-meta-created:$(date -Iseconds)" \
                      -h "x-goog-meta-package:$PACKAGE_NAME" \
                      "$GCP_BUCKET/$(basename "$package_file")"
        
        # Get public URL if bucket is public
        local public_url="$GCP_BUCKET/$(basename "$package_file")"
        print_status "Package URL: $public_url"
        
        # Show file info
        gsutil ls -l "$GCP_BUCKET/$(basename "$package_file")"
        
    else
        print_error "Failed to upload to GCP bucket"
        exit 1
    fi
    
    echo ""
}

# Function to cleanup temporary files
cleanup() {
    print_step "Cleaning up temporary files..."
    
    if [ -d "$PACKAGE_DIR" ]; then
        rm -rf "$PACKAGE_DIR"
        print_status "✓ Removed temporary package directory"
    fi
    
    print_status "Package ready: ${PACKAGE_DIR}.tar.gz"
}

# Function to show final summary
show_summary() {
    local package_file="${PACKAGE_DIR}.tar.gz"
    local package_size=$(du -sh "$package_file" | cut -f1)
    
    print_step "Deployment Package Creation Summary"
    echo ""
    echo "======================================"
    echo "🎉 RAG System Deployment Package Ready!"
    echo "======================================"
    echo ""
    echo "📦 Package: $package_file"
    echo "📏 Size: $package_size"
    echo "🔗 GCP URL: $GCP_BUCKET/$(basename "$package_file")"
    echo "📅 Created: $(date)"
    echo ""
    echo "Next steps on target system:"
    echo "1. Download: gsutil cp $GCP_BUCKET/$(basename "$package_file") ."
    echo "2. Extract: tar -xzf $(basename "$package_file")"
    echo "3. Import: cd $PACKAGE_NAME*/scripts && ./import_images.sh"
    echo "4. Deploy: ./deploy_complete.sh"
    echo "5. Test: ./validate_offline_deployment.sh"
    echo ""
}

# Main execution function
main() {
    echo "=========================================="
    echo "RAG System Deployment Package Creator"
    echo "Version: $PACKAGE_VERSION"
    echo "=========================================="
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --bucket)
                GCP_BUCKET="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --help)
                cat << EOF
Usage: $0 [OPTIONS]

Create a complete RAG system deployment package and upload to GCP.

OPTIONS:
    --bucket BUCKET     GCP bucket URL (default: $GCP_BUCKET)
    --skip-build        Skip Docker image building step  
    --help              Show this help message

NOTES:
    • Automatically creates GCP bucket if it doesn't exist
    • Sets 90-day lifecycle policy on new buckets to manage costs
    • Requires gcloud authentication and appropriate GCP project permissions

EXAMPLES:
    $0
    $0 --bucket gs://my-deployment-bucket
    $0 --skip-build --bucket gs://my-bucket

PREREQUISITES:
    • Docker running
    • gcloud authenticated (gcloud auth login)
    • Project set (gcloud config set project YOUR_PROJECT)
    • ~150GB free disk space

EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute all steps
    check_prerequisites
    ensure_bucket_exists
    
    if [ "$SKIP_BUILD" != "true" ]; then
        build_all_images
    else
        print_warning "Skipping Docker image build (--skip-build specified)"
    fi
    
    create_package_structure
    export_and_upload_images
    copy_deployment_scripts
    copy_documentation
    upload_deployment_package
    
    print_status "🎉 All done! Docker images and deployment package uploaded successfully."
}

# Run main function with all arguments
main "$@"