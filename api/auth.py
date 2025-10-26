"""
Authentication logic for user registration, login, and password management.
Uses bcrypt for secure password hashing.
"""

from passlib.context import CryptContext
from sqlalchemy.orm import Session
from datetime import datetime
import re

from .database import User, create_session_token

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Password validation
MIN_PASSWORD_LENGTH = 6
MAX_PASSWORD_LENGTH = 128


class AuthError(Exception):
    """Custom exception for authentication errors"""
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(self.message)


def hash_password(password: str) -> str:
    """
    Hash a password using bcrypt

    Args:
        password: Plain text password

    Returns:
        Hashed password string
    """
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its hash

    Args:
        plain_password: Plain text password to verify
        hashed_password: Stored hashed password

    Returns:
        True if password matches, False otherwise
    """
    return pwd_context.verify(plain_password, hashed_password)


def validate_username(username: str) -> None:
    """
    Validate username format

    Args:
        username: Username to validate

    Raises:
        AuthError: If username is invalid
    """
    if not username:
        raise AuthError("invalid_username", "Username cannot be empty")

    if len(username) < 3:
        raise AuthError("invalid_username", "Username must be at least 3 characters")

    if len(username) > 50:
        raise AuthError("invalid_username", "Username must be less than 50 characters")

    # Allow alphanumeric, underscore, and dash
    if not re.match(r'^[a-zA-Z0-9_-]+$', username):
        raise AuthError(
            "invalid_username",
            "Username can only contain letters, numbers, underscores, and dashes"
        )


def validate_password(password: str) -> None:
    """
    Validate password strength

    Args:
        password: Password to validate

    Raises:
        AuthError: If password is invalid
    """
    if not password:
        raise AuthError("invalid_password", "Password cannot be empty")

    if len(password) < MIN_PASSWORD_LENGTH:
        raise AuthError(
            "invalid_password",
            f"Password must be at least {MIN_PASSWORD_LENGTH} characters"
        )

    if len(password) > MAX_PASSWORD_LENGTH:
        raise AuthError(
            "invalid_password",
            f"Password must be less than {MAX_PASSWORD_LENGTH} characters"
        )


def register_user(username: str, password: str, db: Session) -> tuple[User, str, datetime]:
    """
    Register a new user

    Args:
        username: Desired username
        password: Plain text password
        db: Database session

    Returns:
        tuple: (User object, session_token, expires_at)

    Raises:
        AuthError: If registration fails
    """
    # Validate inputs
    validate_username(username)
    validate_password(password)

    # Check if username already exists
    existing_user = db.query(User).filter(User.username == username).first()
    if existing_user:
        raise AuthError("username_taken", "Username already exists")

    # Create new user
    hashed_password = hash_password(password)
    user = User(
        username=username,
        hashed_password=hashed_password,
        last_login=datetime.utcnow()
    )

    db.add(user)
    db.commit()
    db.refresh(user)

    # Create session token
    token, expires_at = create_session_token(user.id, db)

    return user, token, expires_at


def login_user(username: str, password: str, db: Session) -> tuple[User, str, datetime]:
    """
    Authenticate user and create session

    Args:
        username: Username
        password: Plain text password
        db: Database session

    Returns:
        tuple: (User object, session_token, expires_at)

    Raises:
        AuthError: If authentication fails
    """
    # Find user
    user = db.query(User).filter(User.username == username).first()

    if not user:
        raise AuthError("invalid_credentials", "Invalid username or password")

    # Verify password
    if not verify_password(password, user.hashed_password):
        raise AuthError("invalid_credentials", "Invalid username or password")

    # Update last login
    user.last_login = datetime.utcnow()
    db.commit()

    # Create session token
    token, expires_at = create_session_token(user.id, db)

    return user, token, expires_at


def change_password(
    user_id: str,
    current_password: str,
    new_password: str,
    db: Session
) -> None:
    """
    Change user password

    Args:
        user_id: User ID
        current_password: Current plain text password
        new_password: New plain text password
        db: Database session

    Raises:
        AuthError: If password change fails
    """
    # Get user
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        raise AuthError("user_not_found", "User not found")

    # Verify current password
    if not verify_password(current_password, user.hashed_password):
        raise AuthError("invalid_password", "Current password is incorrect")

    # Validate new password
    validate_password(new_password)

    # Update password
    user.hashed_password = hash_password(new_password)
    db.commit()
