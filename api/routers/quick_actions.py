from fastapi import APIRouter, HTTPException, Query
from typing import Literal
import yaml
from pathlib import Path

from ..models import QuickAction, QuickActionsResponse
from ..logger import get_logger

router = APIRouter()

# Cache for loaded quick actions
_quick_actions_cache = None

def load_quick_actions():
    """Load quick actions from configuration file"""
    global _quick_actions_cache

    if _quick_actions_cache is not None:
        return _quick_actions_cache

    logger = get_logger()
    config_path = Path(__file__).parent.parent / "config" / "quick_actions.yaml"

    try:
        with open(config_path, 'r', encoding='utf-8') as file:
            config = yaml.safe_load(file)
            _quick_actions_cache = config
            logger.main_logger.info(f"Loaded quick actions configuration from {config_path}")
            return config
    except FileNotFoundError:
        logger.error_logger.error(f"Quick actions config file not found at {config_path}")
        raise HTTPException(
            status_code=500,
            detail="Quick actions configuration not found"
        )
    except Exception as e:
        logger.log_error(e, {"operation": "load_quick_actions", "config_path": str(config_path)})
        raise HTTPException(
            status_code=500,
            detail=f"Failed to load quick actions: {str(e)}"
        )

@router.get("/api/chat/quick-actions", response_model=QuickActionsResponse)
async def get_quick_actions(
    context: Literal["folder", "transcript"] = Query(
        ...,
        description="Context for quick actions: 'folder' for library view, 'transcript' for transcript view"
    )
):
    """
    Get context-aware quick action prompts for chat interface

    - **context**: Either 'folder' (for library/folder view) or 'transcript' (for individual transcript view)

    Returns a list of quick actions with labels, icons, and prompt templates that can be used
    as shortcuts in the chat interface.
    """
    logger = get_logger()

    try:
        logger.main_logger.info(f"Fetching quick actions for context: {context}")

        # Load configuration
        config = load_quick_actions()

        # Get actions for the specified context
        actions_data = config.get(context, [])

        if not actions_data:
            logger.main_logger.warning(f"No quick actions found for context: {context}")
            return QuickActionsResponse(context=context, actions=[])

        # Convert to QuickAction models
        actions = [
            QuickAction(
                id=action["id"],
                label=action["label"],
                icon=action["icon"],
                prompt_template=action["prompt_template"],
                description=action.get("description")
            )
            for action in actions_data
        ]

        logger.main_logger.info(f"Returning {len(actions)} quick actions for context: {context}")

        return QuickActionsResponse(
            context=context,
            actions=actions
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.log_error(e, {"operation": "get_quick_actions", "context": context})
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve quick actions: {str(e)}"
        )

@router.get("/api/chat/quick-actions/health")
async def quick_actions_health_check():
    """Health check for quick actions endpoint"""
    try:
        config = load_quick_actions()

        # Check that both contexts are available
        folder_actions = len(config.get("folder", []))
        transcript_actions = len(config.get("transcript", []))

        return {
            "status": "healthy",
            "service": "quick_actions",
            "message": "Quick actions service is operational",
            "details": {
                "folder_actions": folder_actions,
                "transcript_actions": transcript_actions,
                "total_actions": folder_actions + transcript_actions
            }
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Quick actions service unhealthy: {str(e)}"
        )
