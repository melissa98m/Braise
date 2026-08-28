import random
import uuid
from datetime import date, datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.daily_question import DailyQuestion
from app.models.match import Match
from app.models.message import Message
from app.models.profile import PublicProfile
from app.models.user import User

MAX_MESSAGE_LENGTH = 2000
DEFAULT_MESSAGE_HISTORY = 50
MAX_MESSAGE_HISTORY = 100
QUESTION_OPTION_COUNT = 4

# Bassin de centres d'intérêt "leurres" pour compléter les options du quiz : jamais un intérêt
# réel de la personne visée, seulement de quoi rendre les 3 mauvaises réponses plausibles.
_DECOY_INTERESTS = [
    "Poterie", "Astronomie amateur", "Course à pied", "Jeux de société",
    "Photographie argentique", "Cuisine du monde", "Yoga", "Jardinage",
    "Voile", "Marché aux puces", "Vélo de route", "Aquariophilie",
]


def _get_match_or_404(db: Session, user: User, match_id: uuid.UUID) -> Match:
    # Un match inexistant et un match qui existe mais n'appartient pas à l'appelant renvoient
    # la même erreur générique — même logique anti-énumération que pour les profils/swipes.
    match = db.get(Match, match_id)
    if match is None or user.id not in (match.user_a_id, match.user_b_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Match introuvable.")
    return match


def _other_user_id(match: Match, user: User) -> uuid.UUID:
    return match.user_b_id if match.user_a_id == user.id else match.user_a_id


def assert_match_participant(db: Session, user: User, match_id: uuid.UUID) -> Match:
    return _get_match_or_404(db, user, match_id)


def list_messages(
    db: Session, user: User, match_id: uuid.UUID, limit: int = DEFAULT_MESSAGE_HISTORY
) -> list[Message]:
    _get_match_or_404(db, user, match_id)
    limit = max(1, min(limit, MAX_MESSAGE_HISTORY))
    recent = (
        db.query(Message)
        .filter(Message.match_id == match_id)
        .order_by(Message.created_at.desc())
        .limit(limit)
        .all()
    )
    return list(reversed(recent))


def create_message(db: Session, user: User, match_id: uuid.UUID, body: str) -> Message:
    _get_match_or_404(db, user, match_id)
    body = body.strip()[:MAX_MESSAGE_LENGTH]
    message = Message(match_id=match_id, sender_id=user.id, body=body)
    db.add(message)
    db.commit()
    db.refresh(message)
    return message


def _build_question(
    match_id: uuid.UUID, for_user_id: uuid.UUID, real_interests: list[str], question_date: date
) -> tuple[str, list[str]]:
    # Graine déterministe : la même question (même correct_answer, mêmes options) est
    # reconstruite tant qu'elle n'est pas persistée — évite de générer une réponse différente
    # entre le calcul et l'écriture en base pour la même journée.
    rng = random.Random(f"{match_id}:{for_user_id}:{question_date.isoformat()}")
    correct = rng.choice(real_interests)
    decoy_pool = [interest for interest in _DECOY_INTERESTS if interest not in real_interests]
    rng.shuffle(decoy_pool)
    options = [correct, *decoy_pool[: QUESTION_OPTION_COUNT - 1]]
    rng.shuffle(options)
    return correct, options


def get_or_create_daily_question(db: Session, user: User, match_id: uuid.UUID) -> dict:
    match = _get_match_or_404(db, user, match_id)
    other_id = _other_user_id(match, user)
    today = date.today()

    def _query():
        return (
            db.query(DailyQuestion)
            .filter(
                DailyQuestion.match_id == match_id,
                DailyQuestion.for_user_id == user.id,
                DailyQuestion.question_date == today,
            )
            .one_or_none()
        )

    existing = _query()
    if existing is not None:
        return {
            "options": existing.options,
            "answered": existing.answered,
            "is_correct": existing.is_correct,
        }

    other_profile = db.get(PublicProfile, other_id)
    if other_profile is None or not other_profile.interests:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "Pas encore de question disponible pour ce match."
        )

    correct, options = _build_question(match_id, user.id, other_profile.interests, today)
    db.add(
        DailyQuestion(
            match_id=match_id,
            for_user_id=user.id,
            question_date=today,
            correct_answer=correct,
            options=options,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        # Deux GET concurrents le même jour : l'autre requête a gagné la course, on relit sa ligne.
        db.rollback()
        existing = _query()
        return {
            "options": existing.options,
            "answered": existing.answered,
            "is_correct": existing.is_correct,
        }

    return {"options": options, "answered": False, "is_correct": None}


def answer_daily_question(db: Session, user: User, match_id: uuid.UUID, selected: str) -> dict:
    match = _get_match_or_404(db, user, match_id)
    today = date.today()

    question = (
        db.query(DailyQuestion)
        .filter(
            DailyQuestion.match_id == match_id,
            DailyQuestion.for_user_id == user.id,
            DailyQuestion.question_date == today,
        )
        .one_or_none()
    )
    if question is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aucune question à répondre aujourd'hui.")
    if question.answered:
        raise HTTPException(status.HTTP_409_CONFLICT, "Vous avez déjà répondu aujourd'hui.")
    if selected not in question.options:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Réponse hors des options proposées.")

    is_correct = selected == question.correct_answer
    question.answered = True
    question.is_correct = is_correct
    question.answered_at = datetime.now(timezone.utc)

    # Bonne réponse = +1 flamme partagée pour le match (cahier des charges A.4.3) : le compteur
    # vit sur Match, pas par utilisateur, conformément au modèle posé en Phase 2.
    if is_correct:
        match.flame_count += 1
        if match.unlocked_at is None and match.flame_count >= match.unlock_threshold:
            match.unlocked_at = datetime.now(timezone.utc)

    db.commit()
    return {
        "correct": is_correct,
        "correct_answer": question.correct_answer,
        "flame_count": match.flame_count,
    }
