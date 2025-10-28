#!/bin/bash
# Backup RAG system data
# Usage: ./backup-data.sh [backup_directory]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RAG System - Data Backup ===${NC}"
echo ""

# Default backup directory
BACKUP_DIR=${1:-"/backup"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/rag_backup_$TIMESTAMP"

# Create backup directory
echo "Creating backup directory: $BACKUP_PATH"
mkdir -p "$BACKUP_PATH"
echo ""

# Check if data directories exist
if [ ! -d /data ]; then
    echo -e "${RED}✗ /data directory not found${NC}"
    exit 1
fi

# Backup database
echo -e "${YELLOW}[1/3] Backing up database...${NC}"
if [ -f /data/transcriptions.db ]; then
    cp /data/transcriptions.db "$BACKUP_PATH/transcriptions.db"
    DB_SIZE=$(du -h "$BACKUP_PATH/transcriptions.db" | cut -f1)
    echo -e "${GREEN}✓ Database backed up${NC} (Size: $DB_SIZE)"
else
    echo -e "${YELLOW}⚠ Database not found, skipping${NC}"
fi
echo ""

# Backup uploads
echo -e "${YELLOW}[2/3] Backing up uploads...${NC}"
if [ -d /data/uploads ] && [ "$(ls -A /data/uploads 2>/dev/null)" ]; then
    tar -czf "$BACKUP_PATH/uploads.tar.gz" -C /data uploads/ 2>/dev/null
    UPLOADS_SIZE=$(du -h "$BACKUP_PATH/uploads.tar.gz" | cut -f1)
    FILE_COUNT=$(find /data/uploads -type f | wc -l)
    echo -e "${GREEN}✓ Uploads backed up${NC} (Files: $FILE_COUNT, Size: $UPLOADS_SIZE)"
else
    echo -e "${YELLOW}⚠ No uploads to backup${NC}"
fi
echo ""

# Backup processed files
echo -e "${YELLOW}[3/3] Backing up processed files...${NC}"
if [ -d /data/processed ] && [ "$(ls -A /data/processed 2>/dev/null)" ]; then
    tar -czf "$BACKUP_PATH/processed.tar.gz" -C /data processed/ 2>/dev/null
    PROCESSED_SIZE=$(du -h "$BACKUP_PATH/processed.tar.gz" | cut -f1)
    echo -e "${GREEN}✓ Processed files backed up${NC} (Size: $PROCESSED_SIZE)"
else
    echo -e "${YELLOW}⚠ No processed files to backup${NC}"
fi
echo ""

# Create backup metadata
echo -e "${YELLOW}Creating backup metadata...${NC}"
cat > "$BACKUP_PATH/backup_info.txt" <<EOF
RAG System Backup
=================
Backup Date: $(date)
Backup Path: $BACKUP_PATH
Hostname: $(hostname)

Contents:
---------
EOF

if [ -f "$BACKUP_PATH/transcriptions.db" ]; then
    echo "✓ Database: $(du -h "$BACKUP_PATH/transcriptions.db" | cut -f1)" >> "$BACKUP_PATH/backup_info.txt"
    # Get transcript count
    TRANSCRIPT_COUNT=$(docker exec rag-api-container sqlite3 /app/data/transcriptions.db "SELECT COUNT(*) FROM transcripts;" 2>/dev/null || echo "N/A")
    echo "  Transcripts: $TRANSCRIPT_COUNT" >> "$BACKUP_PATH/backup_info.txt"
fi

if [ -f "$BACKUP_PATH/uploads.tar.gz" ]; then
    echo "✓ Uploads: $(du -h "$BACKUP_PATH/uploads.tar.gz" | cut -f1)" >> "$BACKUP_PATH/backup_info.txt"
fi

if [ -f "$BACKUP_PATH/processed.tar.gz" ]; then
    echo "✓ Processed: $(du -h "$BACKUP_PATH/processed.tar.gz" | cut -f1)" >> "$BACKUP_PATH/backup_info.txt"
fi

echo ""
echo "Docker Images:" >> "$BACKUP_PATH/backup_info.txt"
docker images | grep rag- >> "$BACKUP_PATH/backup_info.txt"

echo -e "${GREEN}✓ Metadata created${NC}"
echo ""

# Calculate total backup size
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)

# Summary
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo ""
echo "Backup Location: $BACKUP_PATH"
echo "Total Size: $TOTAL_SIZE"
echo ""
echo "Backup contains:"
ls -lh "$BACKUP_PATH"
echo ""
echo -e "${YELLOW}To restore this backup:${NC}"
echo "  1. Stop services: ./scripts/stop-all.sh"
echo "  2. Restore database: cp $BACKUP_PATH/transcriptions.db /data/"
echo "  3. Restore uploads: tar -xzf $BACKUP_PATH/uploads.tar.gz -C /data"
echo "  4. Restore processed: tar -xzf $BACKUP_PATH/processed.tar.gz -C /data"
echo "  5. Start services: ./scripts/start-all.sh"
echo ""

# Suggest cleanup
BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "rag_backup_*" -type d | wc -l)
if [ $BACKUP_COUNT -gt 5 ]; then
    echo -e "${YELLOW}Note: Found $BACKUP_COUNT backups in $BACKUP_DIR${NC}"
    echo "Consider cleaning up old backups to save space."
    echo ""
fi
