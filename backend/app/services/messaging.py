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
from app.services import geo, question_llm
from app.services.matches import get_match_or_404, message_is_read, other_user_id

MAX_MESSAGE_LENGTH = 2000
DEFAULT_MESSAGE_HISTORY = 50
MAX_MESSAGE_HISTORY = 100
QUESTION_OPTION_COUNT = 4
MIN_BIO_DECOYS = QUESTION_OPTION_COUNT - 1

# Bassin de centres d'intérêt "leurres" pour compléter les options du quiz : jamais un intérêt
# réel de la personne visée, seulement de quoi rendre les 3 mauvaises réponses plausibles.
_DECOY_INTERESTS = [
    "Poterie", "Astronomie amateur", "Course à pied", "Jeux de société",
    "Photographie argentique", "Cuisine du monde", "Yoga", "Jardinage",
    "Voile", "Marché aux puces", "Vélo de route", "Aquariophilie",
]

# Filet statique pour la catégorie "bio" du quiz, même principe que _DECOY_INTERESTS (jamais une
# vraie bio de qui que ce soit) — sans lui, "bio" ne serait quasiment jamais éligible tôt dans la
# vie de l'app, avant qu'assez d'autres profils publiés aient une bio distincte à emprunter comme
# leurre réel (voir _eligible_categories, MIN_BIO_DECOYS).
_DECOY_BIOS = [
    "Toujours la première à essayer le nouveau resto du quartier.",
    "Sérial procrastinateur, expert en excuses créatives.",
    "Plus à l'aise avec un livre qu'avec les gens, mais on progresse.",
    "Collectionneuse de vinyles et de plantes vertes increvables.",
    "Deux chats, zéro régime alimentaire respecté.",
    "Toujours partant pour un road trip improvisé.",
    "Fan de brunchs du dimanche et de séries qu'on finit en 3 jours.",
    "Jamais sans mon appareil photo, même pour aller chercher le pain.",
    "Meilleur ami des randonnées qui finissent en sieste.",
    "Ni du matin ni du soir, juste fatigué en continu.",
]

_FALLBACK_PROMPT_TEMPLATES = {
    "interest": "Lequel de ces centres d'intérêt appartient vraiment à {name} ?",
    "city": "Laquelle de ces villes est vraiment celle de {name} ?",
    "bio": "Laquelle de ces bios est vraiment celle de {name} ?",
}


def assert_match_participant(db: Session, user: User, match_id: uuid.UUID) -> Match:
    return get_match_or_404(db, user, match_id)


def list_messages(
    db: Session, user: User, match_id: uuid.UUID, limit: int = DEFAULT_MESSAGE_HISTORY
) -> list[dict]:
    match = get_match_or_404(db, user, match_id)
    limit = max(1, min(limit, MAX_MESSAGE_HISTORY))
    recent = (
        db.query(Message)
        .filter(Message.match_id == match_id)
        .order_by(Message.created_at.desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "id": message.id,
            "match_id": message.match_id,
            "sender_id": message.sender_id,
            "body": message.body,
            "created_at": message.created_at,
            "read": message_is_read(match, message),
        }
        for message in reversed(recent)
    ]


def create_message(db: Session, user: User, match_id: uuid.UUID, body: str) -> Message:
    get_match_or_404(db, user, match_id)
    body = body.strip()[:MAX_MESSAGE_LENGTH]
    message = Message(match_id=match_id, sender_id=user.id, body=body)
    db.add(message)
    db.commit()
    db.refresh(message)
    return message


def _decoy_bios(
    db: Session, real_bio: str, exclude_user_ids: set[uuid.UUID], limit: int = 20
) -> list[str]:
    # Toujours de vraies bios d'autres profils publiés — jamais inventées, exactement le même
    # principe que _DECOY_INTERESTS (des leurres réels, juste pas ceux de la personne visée).
    # `exclude_user_ids` retire la personne visée (déjà couverte par le filtre != real_bio, mais
    # ceinture et bretelles) ET la personne qui pose la question — sinon un leurre pourrait être
    # sa propre bio, ce qu'elle reconnaîtrait instantanément et qui rendrait ce jour-là trivial.
    rows = (
        db.query(PublicProfile.bio)
        .filter(
            PublicProfile.is_published.is_(True),
            PublicProfile.bio != "",
            PublicProfile.bio != real_bio,
            PublicProfile.user_id.notin_(exclude_user_ids),
        )
        .distinct()
        .limit(limit)
        .all()
    )
    return [row[0] for row in rows]


def _eligible_categories(
    db: Session, other_profile: PublicProfile, exclude_user_ids: set[uuid.UUID]
) -> tuple[list[str], list[str]]:
    """Catégories de quiz utilisables pour ce profil (au moins une valeur réelle + assez de leurres)
    et, si "bio" en fait partie, le pool de leurres déjà résolu — pour ne pas refaire la requête si
    _build_question la retient. Chaque catégorie ne peut porter que sur une donnée réellement
    stockée (intérêt, ville, bio) : jamais un fait affirmé par le LLM, qui ne sert ailleurs qu'à
    formuler la phrase (voir services/question_llm.py). Les leurres bio combinent de vraies bios
    d'autres profils (préférées, quand il y en a assez) et le filet statique _DECOY_BIOS — sans ce
    filet, "bio" ne serait quasiment jamais proposée tant que la base compte peu d'utilisateurs."""
    categories = []
    if other_profile.interests:
        categories.append("interest")
    if other_profile.city:
        categories.append("city")
    decoy_bios: list[str] = []
    if other_profile.bio:
        real_decoys = _decoy_bios(db, other_profile.bio, exclude_user_ids)
        static_decoys = [b for b in _DECOY_BIOS if b != other_profile.bio]
        decoy_bios = list(dict.fromkeys(real_decoys + static_decoys))
        if len(decoy_bios) >= MIN_BIO_DECOYS:
            categories.append("bio")
    return categories, decoy_bios


def _build_question(
    match_id: uuid.UUID,
    for_user_id: uuid.UUID,
    other_profile: PublicProfile,
    categories: list[str],
    decoy_bios: list[str],
    question_date: date,
) -> tuple[str, str, list[str]]:
    # Graine déterministe : la même catégorie/réponse/options sont reconstruites tant que rien
    # n'est persisté — évite de générer un résultat différent entre le calcul et l'écriture en
    # base pour la même journée.
    rng = random.Random(f"{match_id}:{for_user_id}:{question_date.isoformat()}")
    category = rng.choice(categories)

    if category == "interest":
        correct = rng.choice(other_profile.interests)
        decoy_pool = [i for i in _DECOY_INTERESTS if i not in other_profile.interests]
    elif category == "city":
        correct = other_profile.city
        decoy_pool = [c for c in geo.CITIES if c != correct]
    else:
        correct = other_profile.bio
        decoy_pool = decoy_bios

    rng.shuffle(decoy_pool)
    options = [correct, *decoy_pool[: QUESTION_OPTION_COUNT - 1]]
    rng.shuffle(options)
    return category, correct, options


def _fallback_prompt(category: str, other_display_name: str) -> str:
    name = other_display_name or "cette personne"
    return _FALLBACK_PROMPT_TEMPLATES[category].format(name=name)


def _generate_prompt(other_profile: PublicProfile | None, category: str) -> str:
    display_name = other_profile.display_name if other_profile else ""
    fallback = _fallback_prompt(category, display_name)
    if other_profile is None:
        return fallback
    # services/question_llm.py ne lève jamais et renvoie None sur tout échec (Ollama désactivé,
    # injoignable, trop lent, sortie invalide) — le gabarit statique est le seul chemin garanti.
    generated = question_llm.generate_personalized_prompt(display_name, other_profile.bio, category)
    return generated or fallback


def get_or_create_daily_question(db: Session, user: User, match_id: uuid.UUID) -> dict:
    match = get_match_or_404(db, user, match_id)
    other_id = other_user_id(match, user)
    today = date.today()
    other_profile = db.get(PublicProfile, other_id)

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
        # Le prompt est figé à la création (voir DailyQuestion.prompt) : jamais régénéré ici,
        # qu'il vienne du LLM ou du gabarit — un GET répété (rechargement d'écran) ne doit
        # jamais redéclencher d'appel Ollama, ni refaire la requête des leurres-bios. Repli sur le
        # gabarit "interest" uniquement pour les lignes créées avant l'ajout de cette colonne
        # (prompt/category encore NULL en base) — la seule catégorie qui existait à l'époque.
        prompt = existing.prompt or _fallback_prompt(
            "interest", other_profile.display_name if other_profile else ""
        )
        return {
            "prompt": prompt,
            "options": existing.options,
            "answered": existing.answered,
            "is_correct": existing.is_correct,
            "category": existing.category or "interest",
        }

    if other_profile is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "Pas encore de question disponible pour ce match."
        )

    categories, decoy_bios = _eligible_categories(db, other_profile, {user.id, other_id})
    if not categories:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "Pas encore de question disponible pour ce match."
        )

    category, correct, options = _build_question(
        match_id, user.id, other_profile, categories, decoy_bios, today
    )
    prompt = _generate_prompt(other_profile, category)
    db.add(
        DailyQuestion(
            match_id=match_id,
            for_user_id=user.id,
            question_date=today,
            correct_answer=correct,
            options=options,
            prompt=prompt,
            category=category,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        # Deux GET concurrents le même jour : l'autre requête a gagné la course, on relit sa
        # ligne plutôt que de garder notre propre génération (potentiellement un appel Ollama
        # gaspillé côté perdant, mais rarissime vu la fenêtre de course très courte).
        db.rollback()
        existing = _query()
        return {
            "prompt": existing.prompt
            or _fallback_prompt("interest", other_profile.display_name if other_profile else ""),
            "options": existing.options,
            "answered": existing.answered,
            "is_correct": existing.is_correct,
            "category": existing.category or "interest",
        }

    return {
        "prompt": prompt,
        "options": options,
        "answered": False,
        "is_correct": None,
        "category": category,
    }


def answer_daily_question(db: Session, user: User, match_id: uuid.UUID, selected: str) -> dict:
    match = get_match_or_404(db, user, match_id)
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
