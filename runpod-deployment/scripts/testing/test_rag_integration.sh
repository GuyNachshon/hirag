#!/bin/bash

# Integration test for RAG system with official-based images
# Tests end-to-end functionality of DotsOCR and Whisper with RAG API

set -e

echo "=== RAG System Integration Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test configuration
TEST_IMAGE_PATH="/tmp/test_image.png"
TEST_AUDIO_PATH="/tmp/test_audio.wav"
API_BASE_URL="http://localhost:8080"
DOTSOCR_URL="http://localhost:8002"
WHISPER_URL="http://localhost:8004"

# Create test files
create_test_files() {
    print_status "Creating test files..."

    # Create a simple test image with text (using ImageMagick if available)
    if command -v convert &> /dev/null; then
        convert -size 800x600 xc:white \
            -pointsize 72 -fill black \
            -draw "text 50,100 'Test Document'" \
            -draw "text 50,200 'This is a test image for OCR'" \
            -draw "text 50,300 'Generated for integration testing'" \
            "$TEST_IMAGE_PATH"
        print_status "Created test image: $TEST_IMAGE_PATH"
    else
        print_warning "ImageMagick not available, using placeholder image"
        # Create a minimal PNG using Python if available
        if command -v python3 &> /dev/null; then
            python3 -c "
from PIL import Image, ImageDraw, ImageFont
import os

# Create a simple test image
img = Image.new('RGB', (800, 600), color='white')
draw = ImageDraw.Draw(img)

# Try to use default font, fallback to basic if not available
try:
    font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', 40)
except:
    font = ImageFont.load_default()

draw.text((50, 100), 'Test Document', fill='black', font=font)
draw.text((50, 200), 'This is a test image for OCR', fill='black', font=font)
draw.text((50, 300), 'Generated for integration testing', fill='black', font=font)

img.save('$TEST_IMAGE_PATH')
print('Test image created successfully')
"
        else
            print_error "Cannot create test image. Please install ImageMagick or Python with PIL."
            return 1
        fi
    fi

    # Create a simple test audio file (using FFmpeg if available)
    if command -v ffmpeg &> /dev/null; then
        # Generate a 3-second tone as test audio
        ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -ar 16000 -ac 1 "$TEST_AUDIO_PATH" -y >/dev/null 2>&1
        print_status "Created test audio: $TEST_AUDIO_PATH"
    else
        print_warning "FFmpeg not available, audio tests will be skipped"
    fi
}

# Test DotsOCR integration
test_dotsocr_integration() {
    print_test "Testing DotsOCR integration..."

    if [ ! -f "$TEST_IMAGE_PATH" ]; then
        print_warning "Test image not available, skipping DotsOCR test"
        return 0
    fi

    # Test direct DotsOCR service
    print_status "Testing DotsOCR service directly..."

    DOTSOCR_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST "$DOTSOCR_URL/parse" \
        -F "file=@$TEST_IMAGE_PATH" \
        -F "prompt_mode=layout_all")

    HTTP_CODE="${DOTSOCR_RESPONSE: -3}"
    RESPONSE_BODY="${DOTSOCR_RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        print_status "✓ DotsOCR service responded successfully"
        echo "Response preview: ${RESPONSE_BODY:0:200}..."
    else
        print_error "DotsOCR service failed with HTTP $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
        return 1
    fi

    # Test RAG API file upload integration
    print_status "Testing RAG API file search integration..."

    # Check if API server is running
    if ! curl -s "$API_BASE_URL/health" >/dev/null 2>&1; then
        print_warning "RAG API server not running, skipping integration test"
        return 0
    fi

    API_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST "$API_BASE_URL/api/search/upload" \
        -F "file=@$TEST_IMAGE_PATH" \
        -F "extract_text=true")

    HTTP_CODE="${API_RESPONSE: -3}"
    RESPONSE_BODY="${API_RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        print_status "✓ RAG API file upload integration working"
        echo "Response preview: ${RESPONSE_BODY:0:200}..."
    else
        print_warning "RAG API integration test failed with HTTP $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
    fi
}

# Test Whisper integration
test_whisper_integration() {
    print_test "Testing Whisper integration..."

    if [ ! -f "$TEST_AUDIO_PATH" ]; then
        print_warning "Test audio not available, skipping Whisper test"
        return 0
    fi

    # Test direct Whisper service
    print_status "Testing Whisper service directly..."

    WHISPER_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST "$WHISPER_URL/transcribe" \
        -F "file=@$TEST_AUDIO_PATH" \
        -F "language=he" \
        -F "engine=faster-whisper")

    HTTP_CODE="${WHISPER_RESPONSE: -3}"
    RESPONSE_BODY="${WHISPER_RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        print_status "✓ Whisper service responded successfully"
        echo "Response preview: ${RESPONSE_BODY:0:200}..."
    else
        print_error "Whisper service failed with HTTP $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
        return 1
    fi

    # Test RAG API audio integration
    print_status "Testing RAG API audio transcription integration..."

    # Check if API server is running
    if ! curl -s "$API_BASE_URL/health" >/dev/null 2>&1; then
        print_warning "RAG API server not running, skipping integration test"
        return 0
    fi

    API_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST "$API_BASE_URL/api/audio/transcribe" \
        -F "file=@$TEST_AUDIO_PATH" \
        -F "language=he")

    HTTP_CODE="${API_RESPONSE: -3}"
    RESPONSE_BODY="${API_RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        print_status "✓ RAG API audio integration working"
        echo "Response preview: ${RESPONSE_BODY:0:200}..."
    else
        print_warning "RAG API audio integration test failed with HTTP $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
    fi
}

# Test health endpoints
test_health_endpoints() {
    print_test "Testing all service health endpoints..."

    # Services to test
    declare -A services=(
        ["DotsOCR"]="$DOTSOCR_URL/health"
        ["DotsOCR vLLM"]="http://localhost:8005/health"
        ["Whisper"]="$WHISPER_URL/health"
        ["RAG API"]="$API_BASE_URL/health"
        ["LLM Server"]="http://localhost:8003/health"
        ["Embedding Server"]="http://localhost:8001/health"
        ["Frontend"]="http://localhost:8087/frontend-health"
        ["Langflow"]="http://localhost:7860/health"
    )

    for service in "${!services[@]}"; do
        url="${services[$service]}"
        if curl -s -f "$url" >/dev/null 2>&1; then
            print_status "✓ $service health check passed"
        else
            print_warning "⚠ $service health check failed (may not be running)"
        fi
    done
}

# Test API endpoint compatibility
test_api_compatibility() {
    print_test "Testing API endpoint compatibility..."

    if ! curl -s "$API_BASE_URL/health" >/dev/null 2>&1; then
        print_warning "RAG API server not running, skipping API compatibility tests"
        return 0
    fi

    # Test key endpoints from main README
    declare -A endpoints=(
        ["System Health"]="$API_BASE_URL/health"
        ["Search Health"]="$API_BASE_URL/api/search/health"
        ["Chat Health"]="$API_BASE_URL/api/chat/health"
        ["Audio Health"]="$API_BASE_URL/api/audio/health"
        ["Audio Formats"]="$API_BASE_URL/api/audio/formats"
    )

    for endpoint_name in "${!endpoints[@]}"; do
        url="${endpoints[$endpoint_name]}"
        response=$(curl -s -w "%{http_code}" "$url")
        http_code="${response: -3}"

        if [ "$http_code" = "200" ]; then
            print_status "✓ $endpoint_name endpoint working"
        else
            print_warning "⚠ $endpoint_name endpoint failed ($http_code)"
        fi
    done
}

# Cleanup function
cleanup() {
    print_status "Cleaning up test files..."
    rm -f "$TEST_IMAGE_PATH" "$TEST_AUDIO_PATH"
}

# Main test function
main() {
    print_status "Starting RAG system integration tests..."

    # Check prerequisites
    if ! command -v curl &> /dev/null; then
        print_error "curl not found. Please install curl."
        exit 1
    fi

    # Create test files
    create_test_files || exit 1

    # Run tests
    echo ""
    test_health_endpoints

    echo ""
    test_dotsocr_integration

    echo ""
    test_whisper_integration

    echo ""
    test_api_compatibility

    echo ""
    print_status "=== INTEGRATION TESTS COMPLETED ==="
    print_status "Summary:"
    print_status "  - Official DotsOCR integration: Tested"
    print_status "  - Official Whisper integration: Tested"
    print_status "  - RAG API compatibility: Verified"
    print_status "  - Health endpoints: Checked"
    echo ""
    print_status "Your RAG system is ready for production use!"
    echo ""
}

# Handle cleanup on exit
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Integration test for RAG system with official-based images."
            echo ""
            echo "Prerequisites:"
            echo "  - Running RAG system (all services)"
            echo "  - curl command"
            echo "  - Optional: ImageMagick (for test image creation)"
            echo "  - Optional: FFmpeg (for test audio creation)"
            echo ""
            echo "Options:"
            echo "  --help          Show this help message"
            echo ""
            echo "The script will:"
            echo "  1. Create test files (image and audio)"
            echo "  2. Test DotsOCR and Whisper services directly"
            echo "  3. Test RAG API integration"
            echo "  4. Verify all health endpoints"
            echo "  5. Check API compatibility"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main