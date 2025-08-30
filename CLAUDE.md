# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### HiRAG Setup and Installation
```bash
cd HiRAG
pip install -e .
```

### Running Tests and Evaluation
```bash
# Navigate to evaluation directory
cd HiRAG/eval

# Extract context from datasets
python extract_context.py -i ./datasets/mix -o ./datasets/mix

# Insert context to Graph Database (choose one API)
python insert_context_deepseek.py  # For DeepSeek API
python insert_context_openai.py    # For OpenAI API  
python insert_context_glm.py       # For GLM API

# Run different HiRAG modes
python test_deepseek.py -d mix -m hi           # Full HiRAG
python test_deepseek.py -d mix -m naive        # Naive RAG
python test_deepseek.py -d mix -m hi_nobridge  # HiRAG without bridge
python test_deepseek.py -d mix -m hi_local     # Local knowledge only
python test_deepseek.py -d mix -m hi_global    # Global knowledge only
python test_deepseek.py -d mix -m hi_bridge    # Bridge knowledge only

# Evaluate results
python batch_eval.py -m request -api openai    # Request evaluations
python batch_eval.py -m result -api openai     # Get evaluation results
```

### DotsOCR File Parser
The file parser component uses DotsOCR for document parsing and requires vLLM configuration. Main entry point is `file_parser/dots_ocr/main.py`.

## Architecture Overview

### Three Main Components
1. **HiRAG** - Hierarchical Retrieval-Augmented Generation system
2. **file_parser** - DotsOCR-based document parsing with vision language models
3. **Whisper** - Ivrit AI Whisper for transcription services

### HiRAG Core Architecture
- **Entity Extraction**: Uses `extract_hierarchical_entities` in `hirag/_op.py` to extract entities and relationships from text chunks using structured LLM prompts
- **Hierarchical Clustering**: Implements GMM clustering in `hirag/_cluster_utils.py` with automatic cluster optimization and UMAP dimension reduction
- **Multi-layer Knowledge Graph**: Builds hierarchical knowledge representation with local, global, and bridge connections
- **Query Processing**: Multiple query modes including hierarchical (`hierarchical_query`), naive (`naive_query`), and specialized variants for local/global/bridge knowledge

### Storage Backends
- **Graph Database**: NetworkX (default) or Neo4j via `hirag/_storage/`
- **Vector Database**: NanoVectorDB for embeddings
- **Key-Value Store**: JSON-based storage for caching

### Configuration
Configuration is managed through `HiRAG/config.yaml` supporting multiple LLM providers:
- OpenAI (GPT-4o, text-embedding-ada-002)
- GLM (glm-4-plus, embedding-3)  
- DeepSeek (deepseek-chat)
- vLLM for local models

### File Parser Integration
DotsOCRParser in `file_parser/dots_ocr/parser.py` handles:
- PDF and image file processing
- Vision language model inference via vLLM
- Layout analysis and OCR with configurable prompts
- Multi-threaded processing for batch operations

### Key Files for Development
- `HiRAG/hirag/hirag.py` - Main HiRAG class and API
- `HiRAG/hirag/_op.py` - Core operations (entity extraction, querying)
- `HiRAG/hirag/_cluster_utils.py` - GMM clustering algorithms
- `file_parser/dots_ocr/parser.py` - Document parsing logic
- `HiRAG/config.yaml` - System configuration