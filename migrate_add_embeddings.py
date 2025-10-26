"""
Migration script to add embedding-related columns to existing database.

Adds:
- transcripts.embeddings_generated (BOOLEAN)
- transcript_segments.embedding (TEXT)
"""

import sqlite3
from pathlib import Path
import os

# Get database path
DATABASE_DIR = Path(os.getenv("DATABASE_DIR", "./data"))
DATABASE_PATH = DATABASE_DIR / "transcriptions.db"

if not DATABASE_PATH.exists():
    print(f"Database not found at {DATABASE_PATH}")
    print("No migration needed - database will be created with correct schema on first run.")
    exit(0)

print(f"Migrating database at: {DATABASE_PATH}")

conn = sqlite3.connect(DATABASE_PATH)
cursor = conn.cursor()

# Check if columns already exist
cursor.execute("PRAGMA table_info(transcripts)")
columns = [row[1] for row in cursor.fetchall()]

migrations_needed = []

if 'embeddings_generated' not in columns:
    migrations_needed.append("transcripts.embeddings_generated")

cursor.execute("PRAGMA table_info(transcript_segments)")
segment_columns = [row[1] for row in cursor.fetchall()]

if 'embedding' not in segment_columns:
    migrations_needed.append("transcript_segments.embedding")

if not migrations_needed:
    print("✓ Database already up to date. No migration needed.")
    conn.close()
    exit(0)

print(f"Adding columns: {', '.join(migrations_needed)}")

try:
    # Add embeddings_generated to transcripts table
    if 'embeddings_generated' not in columns:
        print("  Adding transcripts.embeddings_generated...")
        cursor.execute("""
            ALTER TABLE transcripts
            ADD COLUMN embeddings_generated BOOLEAN DEFAULT 0
        """)
        print("  ✓ Added transcripts.embeddings_generated")

    # Add embedding to transcript_segments table
    if 'embedding' not in segment_columns:
        print("  Adding transcript_segments.embedding...")
        cursor.execute("""
            ALTER TABLE transcript_segments
            ADD COLUMN embedding TEXT
        """)
        print("  ✓ Added transcript_segments.embedding")

    conn.commit()
    print("\n✓ Migration completed successfully!")

except Exception as e:
    print(f"\n✗ Migration failed: {e}")
    conn.rollback()
    raise
finally:
    conn.close()
