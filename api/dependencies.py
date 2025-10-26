"""
FastAPI dependencies for authentication and authorization.
"""

from fastapi import Depends, HTTPException, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import Optional

from .database import get_db, validate_session_token, User

# Security scheme for Swagger UI
security = HTTPBearer(auto_error=False)


async def get_current_user(
    authorization: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db)
) -> User:
    """
    Dependency to get current authenticated user from Bearer token.

    Extracts token from Authorization header and validates it against database.

    Args:
        authorization: Bearer token from Authorization header
        db: Database session

    Returns:
        User object if authenticated

    Raises:
        HTTPException: 401 if not authenticated or token invalid/expired
    """
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Not authenticated. Please provide a valid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = authorization.credentials

    # Validate token and get user
    user = validate_session_token(token, db)

    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired authentication token. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


async def get_current_user_optional(
    authorization: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db)
) -> Optional[User]:
    """
    Optional authentication dependency - returns User if authenticated, None otherwise.

    Useful for endpoints that have optional authentication.

    Args:
        authorization: Bearer token from Authorization header
        db: Database session

    Returns:
        User object if authenticated, None otherwise
    """
    if not authorization:
        return None

    token = authorization.credentials
    user = validate_session_token(token, db)

    return user
