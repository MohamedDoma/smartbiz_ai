"""
Workspaces router — create, list, join, settings.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/workspaces", tags=["Workspaces"])


@router.post("")
async def create_workspace():
    # TODO: implement
    return {"message": "not implemented"}


@router.get("")
async def list_workspaces():
    # TODO: implement
    return {"message": "not implemented"}


@router.post("/join")
async def join_workspace():
    # TODO: implement
    return {"message": "not implemented"}


@router.post("/join/{request_id}/approve")
async def approve_join(request_id: str):
    # TODO: implement
    return {"message": "not implemented"}
