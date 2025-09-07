#!/bin/bash

set -e

echo "=========================================="
echo "Generating Comprehensive Test Data"
echo "For Offline RAG System Validation"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[GENERATE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Configuration
TEST_DATA_DIR="./test-data-offline"
DOCS_DIR="$TEST_DATA_DIR/documents"
AUDIO_DIR="$TEST_DATA_DIR/audio"
IMAGES_DIR="$TEST_DATA_DIR/images"
QUERIES_DIR="$TEST_DATA_DIR/queries"
EXPECTED_DIR="$TEST_DATA_DIR/expected"

# Create directory structure
setup_directories() {
    print_header "Setting up test data directories..."
    
    rm -rf "$TEST_DATA_DIR" 2>/dev/null || true
    mkdir -p "$DOCS_DIR" "$AUDIO_DIR" "$IMAGES_DIR" "$QUERIES_DIR" "$EXPECTED_DIR"
    mkdir -p "$TEST_DATA_DIR/working" "$TEST_DATA_DIR/logs" "$TEST_DATA_DIR/cache"
    
    print_status "✓ Test data directories created"
}

# Generate text documents
generate_text_documents() {
    print_header "Generating text documents..."
    
    # Simple text document
    cat > "$DOCS_DIR/simple_document.txt" << 'EOF'
Introduction to Artificial Intelligence

Artificial Intelligence (AI) is a branch of computer science that aims to create intelligent machines that work and react like humans. Some of the activities computers with artificial intelligence are designed for include:
- Speech recognition
- Learning
- Planning
- Problem solving

AI research has been highly successful in developing effective techniques for solving a wide range of problems, from game playing to medical diagnosis.

The field was founded on the assumption that human intelligence can be so precisely described that a machine can be made to simulate it. This raises philosophical questions about the nature of the mind and the ethics of creating artificial beings endowed with human-like intelligence.

Modern AI systems are capable of processing vast amounts of data and identifying patterns that humans might miss. Machine learning, a subset of AI, allows systems to automatically learn and improve from experience without being explicitly programmed.

Deep learning, which uses artificial neural networks with multiple layers, has been particularly successful in areas such as image recognition, natural language processing, and speech synthesis.

The future of AI holds great promise, with potential applications in healthcare, transportation, education, and many other fields. However, it also raises important questions about job displacement, privacy, and the need for ethical guidelines in AI development.
EOF

    # Technical document with Hebrew content
    cat > "$DOCS_DIR/hebrew_tech_doc.txt" << 'EOF'
מדריך טכני למערכות בינה מלאכותית

בינה מלאכותית (AI) היא ענף במדעי המחשב שמטרתו ליצור מכונות חכמות הפועלות ומגיבות כמו בני אדם.

יכולות מרכזיות של מערכות AI:
- זיהוי דיבור והבנת שפה טבעית
- למידה אוטומטית ושיפור ביצועים
- תכנון ופתרון בעיות מורכבות
- עיבוד נתונים בהיקף גדול

טכנולוגיות מתקדמות:
1. למידה עמוקה (Deep Learning)
2. רשתות נוירונליות מלאכותיות
3. עיבוד שפה טבעית (NLP)
4. ראייה ממוחשבת (Computer Vision)

מערכות AI מודרניות מסוגלות לעבד כמויות עצומות של נתונים ולזהות דפוסים שבני אדם עלולים להחמיץ. למידת מכונה, שהיא תת-קטגוריה של AI, מאפשרת למערכות ללמוד ולהשתפר באופן אוטומטי מהניסיון ללא תכנות מפורש.

יישומים עתידיים כוללים רפואה, תחבורה, חינוך ותחומים נוספים רבים.
EOF

    # Complex document for hierarchical processing
    cat > "$DOCS_DIR/complex_research_paper.txt" << 'EOF'
Advanced Hierarchical Retrieval-Augmented Generation Systems
A Comprehensive Study of Multi-Modal Information Processing

Abstract:
This paper presents a novel approach to information retrieval using hierarchical clustering and multi-modal processing capabilities. Our system demonstrates significant improvements in accuracy and relevance when processing diverse document types.

1. Introduction
Retrieval-Augmented Generation (RAG) systems have revolutionized how we process and query large document collections. Traditional RAG approaches often struggle with complex, hierarchical information structures and multi-modal content.

1.1 Problem Statement
Current RAG systems face several challenges:
- Limited understanding of document hierarchy
- Poor handling of multi-modal content (text, images, audio)
- Scalability issues with large document collections
- Context preservation across document boundaries

1.2 Our Approach
We propose HiRAG (Hierarchical Retrieval-Augmented Generation), which addresses these limitations through:
- Advanced clustering algorithms for document organization
- Multi-modal processing capabilities
- Context-aware retrieval mechanisms
- Scalable architecture design

2. Methodology

2.1 Document Processing Pipeline
Our system processes documents through multiple stages:
1. Initial parsing and content extraction
2. Entity recognition and relationship mapping
3. Hierarchical clustering based on semantic similarity
4. Multi-modal content analysis
5. Index construction and optimization

2.2 Hierarchical Clustering Algorithm
We employ a novel Gaussian Mixture Model (GMM) approach with automatic cluster optimization. The algorithm dynamically determines the optimal number of clusters based on:
- Silhouette score analysis
- Davies-Bouldin index
- Calinski-Harabasz score
- Custom semantic coherence metrics

2.3 Multi-Modal Processing
Our system handles various content types:
- Text documents (PDF, DOCX, TXT)
- Images with OCR capabilities
- Audio transcription (Hebrew and English)
- Structured data (JSON, XML, CSV)

3. Results and Evaluation

3.1 Performance Metrics
We evaluated our system using several metrics:
- Query response accuracy: 94.2% (+12% over baseline)
- Response time: 1.3s average (2.1s baseline)
- Context preservation: 89.7% (+15% over baseline)
- Multi-modal integration: 91.3% accuracy

3.2 Scalability Testing
The system was tested with document collections ranging from 1,000 to 100,000 documents:
- Linear scaling in processing time
- Constant memory usage per document
- Maintained accuracy across all collection sizes

4. Conclusion
Our HiRAG system demonstrates significant improvements over traditional RAG approaches, particularly in handling complex, multi-modal content. The hierarchical clustering approach enables better context preservation and more relevant query responses.

Future work will focus on:
- Integration with streaming data sources
- Real-time learning and adaptation
- Enhanced multilingual support
- Performance optimization for edge deployment

References:
1. Smith, J. et al. "Advanced Information Retrieval Systems" (2023)
2. Johnson, M. "Hierarchical Document Processing" (2023)
3. Chen, L. "Multi-Modal AI Systems" (2024)
EOF

    # Create a simple PDF using HTML conversion if available
    if command -v wkhtmltopdf > /dev/null 2>&1; then
        echo "<html><body><h1>PDF Test Document</h1><p>This is a test PDF document for OCR and document processing validation.</p><p>It contains <strong>formatted text</strong> and <em>various styling</em> to test document parsing capabilities.</p></body></html>" | wkhtmltopdf - "$DOCS_DIR/test_document.pdf" 2>/dev/null || true
    fi
    
    print_status "✓ Generated text documents with Hebrew and English content"
}

# Generate audio test files
generate_audio_files() {
    print_header "Generating audio test files..."
    
    # Check if ffmpeg is available
    if command -v ffmpeg > /dev/null 2>&1; then
        # Generate Hebrew test audio (silence with metadata)
        ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -ar 16000 -ac 1 \
               -metadata title="Hebrew Test Audio" \
               -metadata comment="Test file for Hebrew Whisper transcription" \
               "$AUDIO_DIR/hebrew_test.wav" -loglevel quiet 2>/dev/null || true
        
        # Generate English test audio
        ffmpeg -f lavfi -i "sine=frequency=880:duration=2" -ar 16000 -ac 1 \
               -metadata title="English Test Audio" \
               "$AUDIO_DIR/english_test.wav" -loglevel quiet 2>/dev/null || true
               
        # Generate longer audio for stress testing
        ffmpeg -f lavfi -i "sine=frequency=220:duration=10" -ar 16000 -ac 1 \
               "$AUDIO_DIR/long_audio_test.wav" -loglevel quiet 2>/dev/null || true
               
        print_status "✓ Generated audio test files"
    else
        print_warning "ffmpeg not available - creating placeholder audio files"
        echo "# Placeholder audio file for testing" > "$AUDIO_DIR/hebrew_test.txt"
        echo "# Placeholder audio file for testing" > "$AUDIO_DIR/english_test.txt"
    fi
}

# Generate test images
generate_test_images() {
    print_header "Generating test images..."
    
    # Check if ImageMagick is available
    if command -v convert > /dev/null 2>&1; then
        # Simple text image
        convert -size 800x600 xc:white \
                -font Arial -pointsize 24 -fill black \
                -draw "text 50,100 'Test Document Title'" \
                -draw "text 50,150 'This is a test image with text content'" \
                -draw "text 50,200 'for OCR and vision processing validation.'" \
                -draw "text 50,300 'Hebrew text: בדיקה של טקסט בעברית'" \
                -draw "text 50,350 'Numbers: 12345 and symbols: @#$%'" \
                "$IMAGES_DIR/text_image.png" 2>/dev/null || true
                
        # Simple diagram/chart
        convert -size 600x400 xc:white \
                -stroke black -strokewidth 2 \
                -draw "rectangle 100,100 500,300" \
                -draw "line 100,200 500,200" \
                -draw "line 300,100 300,300" \
                -fill black -font Arial -pointsize 16 \
                -draw "text 120,130 'Q1: 25%'" \
                -draw "text 320,130 'Q2: 35%'" \
                -draw "text 120,230 'Q3: 20%'" \
                -draw "text 320,230 'Q4: 20%'" \
                "$IMAGES_DIR/chart_image.png" 2>/dev/null || true
                
        print_status "✓ Generated test images with text and diagrams"
    else
        print_warning "ImageMagick not available - creating placeholder images"
        echo "# Placeholder image file for OCR testing" > "$IMAGES_DIR/text_image.txt"
        echo "# Placeholder chart image for testing" > "$IMAGES_DIR/chart_image.txt"
    fi
}

# Generate test queries and expected responses
generate_queries() {
    print_header "Generating test queries..."
    
    cat > "$QUERIES_DIR/basic_queries.json" << 'EOF'
{
  "queries": [
    {
      "id": "q1",
      "query": "What is artificial intelligence?",
      "type": "definition",
      "expected_keywords": ["artificial intelligence", "computer science", "intelligent machines", "humans"]
    },
    {
      "id": "q2", 
      "query": "What are the main capabilities of AI systems?",
      "type": "list",
      "expected_keywords": ["speech recognition", "learning", "planning", "problem solving"]
    },
    {
      "id": "q3",
      "query": "מה זה בינה מלאכותית?",
      "type": "definition_hebrew",
      "expected_keywords": ["בינה מלאכותית", "מדעי המחשב", "מכונות חכמות"]
    },
    {
      "id": "q4",
      "query": "Explain the HiRAG methodology",
      "type": "complex",
      "expected_keywords": ["hierarchical", "clustering", "multi-modal", "processing"]
    },
    {
      "id": "q5",
      "query": "What were the performance results of the HiRAG system?",
      "type": "facts",
      "expected_keywords": ["94.2%", "accuracy", "1.3s", "response time"]
    }
  ]
}
EOF

    cat > "$QUERIES_DIR/stress_queries.json" << 'EOF'
{
  "stress_queries": [
    {
      "id": "s1",
      "query": "Provide a comprehensive analysis of all AI capabilities mentioned in the documents, including performance metrics, methodologies, and future applications, with specific focus on multi-modal processing and Hebrew language support capabilities.",
      "type": "comprehensive",
      "difficulty": "high"
    },
    {
      "id": "s2",
      "query": "Compare and contrast traditional RAG systems with the HiRAG approach, detailing specific technical improvements and quantitative performance gains.",
      "type": "comparison",
      "difficulty": "high"
    },
    {
      "id": "s3",
      "query": "What is the relationship between deep learning and neural networks in the context of AI development?",
      "type": "relationship",
      "difficulty": "medium"
    }
  ]
}
EOF

    # Generate expected responses
    cat > "$EXPECTED_DIR/basic_responses.json" << 'EOF'
{
  "expected_responses": {
    "q1": {
      "should_contain": [
        "branch of computer science",
        "intelligent machines",
        "work and react like humans"
      ],
      "should_not_contain": ["irrelevant", "error"],
      "min_length": 100
    },
    "q2": {
      "should_contain": [
        "speech recognition",
        "learning",
        "planning",
        "problem solving"
      ],
      "format": "list"
    },
    "q3": {
      "should_contain": [
        "מדעי המחשב",
        "מכונות חכמות"
      ],
      "language": "hebrew"
    }
  }
}
EOF

    print_status "✓ Generated test queries with expected responses"
}

# Generate configuration for testing
generate_test_config() {
    print_header "Generating test configuration..."
    
    cat > "$TEST_DATA_DIR/test_config.yaml" << 'EOF'
# Test Configuration for Offline RAG System
test_config:
  data_paths:
    documents: "./test-data-offline/documents"
    audio: "./test-data-offline/audio"
    images: "./test-data-offline/images"
    queries: "./test-data-offline/queries"
    expected: "./test-data-offline/expected"
    working: "./test-data-offline/working"
  
  services:
    api_url: "http://localhost:8080"
    embedding_url: "http://localhost:8001" 
    dotsocr_url: "http://localhost:8002"
    llm_url: "http://localhost:8003"
    whisper_url: "http://localhost:8004"
  
  test_parameters:
    timeout_seconds: 30
    max_retries: 3
    concurrent_queries: 5
    stress_test_duration: 300
    
  gpu_config:
    expected_cores: 8
    core_assignments:
      dotsocr: [0, 1]
      llm: [2, 3, 4, 5]
      embedding: [6]
      whisper: [7]
      
  performance_thresholds:
    query_response_time_ms: 5000
    document_processing_time_s: 30
    audio_transcription_time_s: 10
    image_ocr_time_s: 15
    
  validation_checks:
    - health_endpoints
    - service_communication
    - document_processing
    - query_functionality
    - multi_modal_processing
    - gpu_utilization
    - performance_benchmarks
EOF

    print_status "✓ Generated comprehensive test configuration"
}

# Generate README for test data
generate_test_readme() {
    print_header "Generating test data documentation..."
    
    cat > "$TEST_DATA_DIR/README.md" << 'EOF'
# RAG System Test Data

This directory contains comprehensive test data for validating the RAG system in offline environments.

## Directory Structure

```
test-data-offline/
├── documents/           # Text documents, PDFs for processing
├── audio/              # Audio files for transcription testing  
├── images/             # Images for OCR and vision processing
├── queries/            # Test queries in JSON format
├── expected/           # Expected response patterns
├── working/            # Temporary processing directory
├── logs/               # Test execution logs
├── cache/              # System cache directory
├── test_config.yaml    # Test configuration
└── README.md           # This file
```

## Test Data Categories

### Documents
- **simple_document.txt**: Basic English AI overview
- **hebrew_tech_doc.txt**: Hebrew technical documentation  
- **complex_research_paper.txt**: Multi-section research paper
- **test_document.pdf**: PDF with formatting (if generated)

### Audio Files
- **hebrew_test.wav**: Hebrew audio for Whisper testing
- **english_test.wav**: English audio sample
- **long_audio_test.wav**: Extended audio for performance testing

### Images  
- **text_image.png**: Text-heavy image for OCR
- **chart_image.png**: Diagram/chart for vision processing

### Queries
- **basic_queries.json**: Standard question set
- **stress_queries.json**: Complex, long-form queries

### Expected Responses
- **basic_responses.json**: Validation patterns for basic queries

## Usage

This test data is automatically used by the validation scripts:
- `test_offline_complete.sh`
- `validate_8core_performance.sh` 
- `test_e2e_rag_workflow.sh`
- `benchmark_h100_deployment.sh`

## Customization

You can add your own test files to any directory. Update `test_config.yaml` to include new test parameters or thresholds as needed.

## Regeneration

To regenerate all test data:
```bash
./deploy/generate_test_data.sh
```

This will clean and recreate all test files with current configurations.
EOF

    print_status "✓ Generated test data documentation"
}

# Create manifest file
create_manifest() {
    print_header "Creating test data manifest..."
    
    cat > "$TEST_DATA_DIR/manifest.json" << EOF
{
  "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "1.0.0",
  "description": "Comprehensive test data for offline RAG system validation",
  "files": {
    "documents": [
      "simple_document.txt",
      "hebrew_tech_doc.txt", 
      "complex_research_paper.txt"
    ],
    "audio": [
      "hebrew_test.wav",
      "english_test.wav",
      "long_audio_test.wav"
    ],
    "images": [
      "text_image.png",
      "chart_image.png"
    ],
    "queries": [
      "basic_queries.json",
      "stress_queries.json"
    ],
    "expected": [
      "basic_responses.json"
    ],
    "config": [
      "test_config.yaml"
    ]
  },
  "statistics": {
    "total_files": $(find "$TEST_DATA_DIR" -type f | wc -l),
    "total_size_mb": "$(du -sm "$TEST_DATA_DIR" | cut -f1)",
    "document_count": $(find "$DOCS_DIR" -type f | wc -l),
    "audio_count": $(find "$AUDIO_DIR" -type f | wc -l),
    "image_count": $(find "$IMAGES_DIR" -type f | wc -l)
  }
}
EOF

    print_status "✓ Created test data manifest"
}

# Main execution
main() {
    print_header "Starting comprehensive test data generation..."
    
    setup_directories
    generate_text_documents  
    generate_audio_files
    generate_test_images
    generate_queries
    generate_test_config
    generate_test_readme
    create_manifest
    
    echo ""
    echo "=========================================="
    echo "Test Data Generation Complete!"
    echo "=========================================="
    
    print_status "Generated test data in: $TEST_DATA_DIR"
    print_status "Total files: $(find "$TEST_DATA_DIR" -type f | wc -l)"
    print_status "Total size: $(du -sh "$TEST_DATA_DIR" | cut -f1)"
    
    echo ""
    print_status "Test data includes:"
    print_status "• Documents: $(ls "$DOCS_DIR" | wc -l) files (English + Hebrew)"
    print_status "• Audio: $(ls "$AUDIO_DIR" | wc -l) files (WAV format for Whisper)"
    print_status "• Images: $(ls "$IMAGES_DIR" 2>/dev/null | wc -l) files (OCR testing)"
    print_status "• Queries: $(ls "$QUERIES_DIR" | wc -l) JSON files (basic + stress)"
    print_status "• Config: Complete test configuration and documentation"
    
    echo ""
    print_status "Ready for offline validation testing!"
    print_status "Next steps:"
    print_status "  1. ./deploy/test_offline_complete.sh"
    print_status "  2. ./deploy/validate_8core_performance.sh"
    print_status "  3. ./deploy/test_e2e_rag_workflow.sh"
}

# Handle command line options
if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Generate comprehensive test data for offline RAG system validation"
    echo ""
    echo "Options:"
    echo "  --help       Show this help"
    echo "  --clean      Remove existing test data before generation"
    echo ""
    echo "Generated test data includes:"
    echo "  • Text documents (English + Hebrew)"
    echo "  • Audio files for transcription testing"
    echo "  • Images for OCR and vision processing"
    echo "  • Test queries and expected responses"
    echo "  • Configuration and documentation"
    exit 0
fi

if [[ "$1" == "--clean" ]]; then
    print_header "Cleaning existing test data..."
    rm -rf "$TEST_DATA_DIR" 2>/dev/null || true
    print_status "✓ Existing test data cleaned"
fi

# Run main generation
main "$@"