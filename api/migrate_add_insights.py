"""
Database migration to add insights column to transcripts table
"""
import sqlite3
import os

# Database path
db_path = os.path.join("data", "transcriptions.db")

def migrate():
    if not os.path.exists(db_path):
        print(f"Database not found at {db_path}")
        return

    print(f"Migrating database at: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if insights column already exists
    cursor.execute("PRAGMA table_info(transcripts)")
    columns = [col[1] for col in cursor.fetchall()]

    if 'insights' in columns:
        print("✓ Insights column already exists. No migration needed.")
        conn.close()
        return

    # Add insights column
    try:
        cursor.execute("ALTER TABLE transcripts ADD COLUMN insights TEXT")
        conn.commit()
        print("✓ Successfully added insights column to transcripts table")
    except Exception as e:
        print(f"Error adding insights column: {e}")
        conn.rollback()
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()
