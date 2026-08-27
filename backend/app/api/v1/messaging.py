from fastapi import APIRouter

router = APIRouter(prefix="/messaging", tags=["messaging"])


@router.get("/ping")
def ping():
    return {"module": "Messagerie & Flammes", "status": "stub — Phase 3"}
