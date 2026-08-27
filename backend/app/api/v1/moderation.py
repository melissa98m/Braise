from fastapi import APIRouter

router = APIRouter(prefix="/moderation", tags=["moderation"])


@router.get("/ping")
def ping():
    return {"module": "Confiance & Modération", "status": "stub — Phase 4"}
