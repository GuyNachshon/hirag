#!/usr/bin/env python3
"""
Database initialization script.

Run this script to:
1. Create all database tables
2. Optionally create a default admin user

Usage:
    python -m api.init_db
    python -m api.init_db --create-admin
"""

import argparse
import sys
from pathlib import Path

# Add parent directory to path so we can import api modules
sys.path.insert(0, str(Path(__file__).parent.parent))

from api.database import init_db, get_db
from api.auth import register_user, AuthError


def create_admin_user(username: str = "admin", password: str = "admin123"):
    """
    Create an admin user for initial setup.

    Args:
        username: Admin username
        password: Admin password

    Returns:
        True if created, False if already exists
    """
    db = next(get_db())

    try:
        user, token, expires_at = register_user(username, password, db)
        print(f"✓ Admin user created successfully:")
        print(f"  Username: {user.username}")
        print(f"  User ID: {user.id}")
        print(f"  Token: {token}")
        print(f"  Expires: {expires_at}")
        print(f"\n⚠️  IMPORTANT: Change this password after first login!")
        return True

    except AuthError as e:
        if e.code == "username_taken":
            print(f"ℹ Admin user '{username}' already exists")
            return False
        else:
            print(f"✗ Error creating admin user: {e.message}")
            return False

    finally:
        db.close()


def main():
    """Main initialization function"""
    parser = argparse.ArgumentParser(
        description="Initialize the transcription database"
    )
    parser.add_argument(
        "--create-admin",
        action="store_true",
        help="Create a default admin user (username: admin, password: admin123)"
    )
    parser.add_argument(
        "--admin-username",
        default="admin",
        help="Admin username (default: admin)"
    )
    parser.add_argument(
        "--admin-password",
        default="admin123",
        help="Admin password (default: admin123)"
    )

    args = parser.parse_args()

    print("=" * 60)
    print("RAG Transcription System - Database Initialization")
    print("=" * 60)
    print()

    # Initialize database tables
    print("Creating database tables...")
    try:
        init_db()
        print("✓ Database tables created successfully")
        print()
    except Exception as e:
        print(f"✗ Error creating database tables: {e}")
        sys.exit(1)

    # Create admin user if requested
    if args.create_admin:
        print("Creating admin user...")
        create_admin_user(args.admin_username, args.admin_password)
        print()

    print("=" * 60)
    print("Initialization complete!")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Start the API server: uvicorn api.main:app --reload")
    print("2. Access API docs: http://localhost:8080/docs")
    if args.create_admin:
        print(f"3. Login with username '{args.admin_username}' and change password")
    else:
        print("3. Register a new user account")
    print()


if __name__ == "__main__":
    main()
