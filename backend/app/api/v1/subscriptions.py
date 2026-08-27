from fastapi import APIRouter

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.get("/ping")
def ping():
    return {"module": "Monétisation (Braise+)", "status": "stub — Phase 5"}
