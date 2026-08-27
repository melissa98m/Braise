from fastapi import APIRouter

router = APIRouter(prefix="/profiles", tags=["profiles"])


@router.get("/ping")
def ping():
    return {"module": "Identité & Profils", "status": "stub — Phase 1"}
