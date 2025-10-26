"""
Authentication endpoints for user registration, login, and session management.
"""

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session

from ..database import get_db, invalidate_session_token
from ..dependencies import get_current_user
from ..models import (
    RegisterRequest,
    LoginRequest,
    AuthResponse,
    UserResponse,
    ChangePasswordRequest
)
from ..auth import register_user, login_user, change_password, AuthError
from ..logger import get_logger

router = APIRouter(prefix="/api/auth", tags=["Authentication"])
logger = get_logger()


@router.post("/register", response_model=AuthResponse)
async def register(
    request: RegisterRequest,
    db: Session = Depends(get_db)
):
    """
    Register a new user account.

    Args:
        request: Registration details (username, password)
        db: Database session

    Returns:
        AuthResponse with user info and session token

    Raises:
        HTTPException: 400 if username taken or validation fails
    """
    try:
        logger.main_logger.info(f"Registration attempt for username: {request.username}")

        user, token, expires_at = register_user(
            username=request.username,
            password=request.password,
            db=db
        )

        logger.main_logger.info(f"User registered successfully: {user.username} (ID: {user.id})")

        return AuthResponse(
            user_id=user.id,
            username=user.username,
            token=token,
            expires_at=expires_at
        )

    except AuthError as e:
        logger.log_error(e, {"username": request.username, "error_code": e.code})
        raise HTTPException(status_code=400, detail=e.message)


@router.post("/login", response_model=AuthResponse)
async def login(
    request: LoginRequest,
    db: Session = Depends(get_db)
):
    """
    Login with username and password.

    Args:
        request: Login credentials (username, password)
        db: Database session

    Returns:
        AuthResponse with user info and session token

    Raises:
        HTTPException: 401 if credentials are invalid
    """
    try:
        logger.main_logger.info(f"Login attempt for username: {request.username}")

        user, token, expires_at = login_user(
            username=request.username,
            password=request.password,
            db=db
        )

        logger.main_logger.info(f"User logged in successfully: {user.username} (ID: {user.id})")

        return AuthResponse(
            user_id=user.id,
            username=user.username,
            token=token,
            expires_at=expires_at
        )

    except AuthError as e:
        logger.log_error(e, {"username": request.username, "error_code": e.code})
        raise HTTPException(status_code=401, detail=e.message)


@router.post("/logout")
async def logout(
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Logout and invalidate current session token.

    Requires authentication.

    Returns:
        Success message
    """
    # Note: In a real implementation, we'd need to extract the token from the request
    # For now, we'll just log the logout - the frontend can remove the token from storage
    logger.main_logger.info(f"User logged out: {current_user.username} (ID: {current_user.id})")

    return {"message": "Logged out successfully"}


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    current_user = Depends(get_current_user)
):
    """
    Get current authenticated user information.

    Requires authentication.

    Returns:
        UserResponse with user details
    """
    return UserResponse(
        user_id=current_user.id,
        username=current_user.username,
        created_at=current_user.created_at
    )


@router.post("/change-password")
async def change_user_password(
    request: ChangePasswordRequest,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Change current user's password.

    Requires authentication.

    Args:
        request: Current and new password
        current_user: Authenticated user
        db: Database session

    Returns:
        Success message

    Raises:
        HTTPException: 400 if current password incorrect or validation fails
    """
    try:
        logger.main_logger.info(f"Password change attempt for user: {current_user.username}")

        change_password(
            user_id=current_user.id,
            current_password=request.current_password,
            new_password=request.new_password,
            db=db
        )

        logger.main_logger.info(f"Password changed successfully for user: {current_user.username}")

        return {"message": "Password changed successfully"}

    except AuthError as e:
        logger.log_error(e, {"user_id": current_user.id, "error_code": e.code})
        raise HTTPException(status_code=400, detail=e.message)


@router.get("/health")
async def auth_health():
    """Check authentication service health"""
    return {
        "status": "healthy",
        "service": "authentication"
    }
