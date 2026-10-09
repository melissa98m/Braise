from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_optional_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.feedback import ClientErrorIn, FeedbackIn, FeedbackOut
from app.services import client_errors as client_errors_service
from app.services import feedback as feedback_service

router = APIRouter(tags=["feedback"])


@router.post("/feedback", response_model=FeedbackOut, status_code=status.HTTP_201_CREATED)
def send_feedback(
    payload: FeedbackIn,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    feedback_service.create_feedback(db, user, payload, request.headers.get("user-agent"))
    return FeedbackOut(message="Merci ! Votre retour a bien été envoyé.")


@router.post("/client-errors", status_code=status.HTTP_204_NO_CONTENT)
def report_client_error(
    payload: ClientErrorIn,
    request: Request,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    client_errors_service.record_client_error(
        db,
        payload,
        user_id=user.id if user else None,
        client_ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
