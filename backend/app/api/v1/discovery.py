from fastapi import APIRouter

router = APIRouter(prefix="/discovery", tags=["discovery"])


@router.get("/ping")
def ping():
    return {"module": "Matching & Découverte", "status": "stub — Phase 2"}
