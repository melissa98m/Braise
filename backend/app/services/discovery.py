import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.match import Match
from app.models.profile import PublicProfile
from app.models.swipe import Swipe, SwipeDecision
from app.models.user import User
from app.services.avatar import avatar_spec_from_seed
from app.services.matches import other_user_id
from app.services.profiles import compute_age
from app.services.subscriptions import can_create_new_match

# Borne le coût de calcul par requête : on ne score jamais plus que ce pool, même si le
# nombre de profils publiés grandit beaucoup au-delà de ce qu'un seul feed doit renvoyer.
MAX_CANDIDATE_POOL = 200
MAX_FEED_LIMIT = 50


def _ordered_pair(id1: uuid.UUID, id2: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    return (id1, id2) if str(id1) < str(id2) else (id2, id1)


def _jaccard(a: list[str], b: list[str]) -> float:
    set_a, set_b = set(a), set(b)
    if not set_a or not set_b:
        return 0.0
    return len(set_a & set_b) / len(set_a | set_b)


def get_feed(db: Session, user: User, limit: int) -> list[dict]:
    limit = max(1, min(limit, MAX_FEED_LIMIT))

    my_profile = db.get(PublicProfile, user.id)
    my_interests = my_profile.interests if my_profile else []

    already_swiped = select(Swipe.to_user_id).where(Swipe.from_user_id == user.id)
    query = db.query(PublicProfile).filter(
        PublicProfile.user_id != user.id,
        PublicProfile.is_published.is_(True),
        PublicProfile.user_id.notin_(already_swiped),
    )
    # Filtres de découverte de base (cahier des charges A.5) : genre recherché poussé en SQL
    # (égalité simple, réduit le pool avant le tri) ; tranche d'âge appliquée en Python ci-dessous
    # comme le score de compatibilité, l'âge n'étant pas une colonne stockée (voir compute_age) —
    # même choix de conception que le reste de ce module : pas de requête SQL sur date de
    # naissance pour un filtre qui reste, de toute façon, borné par MAX_CANDIDATE_POOL.
    if my_profile is not None and my_profile.looking_for_gender is not None:
        query = query.filter(PublicProfile.gender == my_profile.looking_for_gender)

    candidates = query.order_by(PublicProfile.updated_at.desc()).limit(MAX_CANDIDATE_POOL).all()

    age_min = my_profile.age_min if my_profile else None
    age_max = my_profile.age_max if my_profile else None

    # Batché en une requête IN(...) plutôt qu'un aller-retour par candidat — même règle que
    # list_my_matches (services/matches, cf. CLAUDE.md) pour éviter un N+1.
    verified_by_id = dict(
        db.query(User.id, User.is_verified).filter(
            User.id.in_([profile.user_id for profile in candidates])
        )
    )

    scored = []
    for profile in candidates:
        age = compute_age(profile.birth_date)
        if age_min is not None and age < age_min:
            continue
        if age_max is not None and age > age_max:
            continue
        common = sorted(set(my_interests) & set(profile.interests))
        scored.append(
            {
                "user_id": profile.user_id,
                "display_name": profile.display_name,
                "age": age,
                "bio": profile.bio,
                "interests": profile.interests,
                "avatar": avatar_spec_from_seed(profile.avatar_seed),
                "common_interests": common,
                "compatibility_score": round(_jaccard(my_interests, profile.interests), 2),
                "is_verified": verified_by_id.get(profile.user_id, False),
            }
        )

    scored.sort(key=lambda item: item["compatibility_score"], reverse=True)
    return scored[:limit]


def record_swipe(
    db: Session, user: User, to_user_id: uuid.UUID, decision: SwipeDecision
) -> bool:
    if to_user_id == user.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Impossible de se swiper soi-même.")

    if decision == SwipeDecision.LIKE and not can_create_new_match(db, user):
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            "Limite de matchs gratuits atteinte. Passez à Braise+ pour continuer à liker.",
        )

    # Un profil inexistant et un profil non publié renvoient la même erreur générique :
    # ne pas laisser un client distinguer "n'existe pas" de "existe mais pas publié".
    target_profile = db.get(PublicProfile, to_user_id)
    if target_profile is None or not target_profile.is_published:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profil introuvable.")

    existing = (
        db.query(Swipe)
        .filter(Swipe.from_user_id == user.id, Swipe.to_user_id == to_user_id)
        .one_or_none()
    )
    if existing is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce profil a déjà reçu une réponse.")

    db.add(Swipe(from_user_id=user.id, to_user_id=to_user_id, decision=decision.value))
    try:
        db.flush()
    except IntegrityError:
        # Deux requêtes concurrentes sur la même paire : la contrainte unique tranche,
        # pas un bug applicatif.
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce profil a déjà reçu une réponse.")

    matched = False
    if decision == SwipeDecision.LIKE:
        reverse_like = (
            db.query(Swipe)
            .filter(
                Swipe.from_user_id == to_user_id,
                Swipe.to_user_id == user.id,
                Swipe.decision == SwipeDecision.LIKE.value,
            )
            .one_or_none()
        )
        if reverse_like is not None:
            user_a_id, user_b_id = _ordered_pair(user.id, to_user_id)
            try:
                with db.begin_nested():
                    db.add(Match(user_a_id=user_a_id, user_b_id=user_b_id))
                matched = True
            except IntegrityError:
                # Les deux swipes "like" sont arrivés en même temps : l'autre requête a
                # déjà créé le match, on ne le recrée pas mais c'est bien un match.
                matched = True

    db.commit()
    return matched


def list_my_matches(db: Session, user: User) -> list[dict]:
    matches = (
        db.query(Match)
        .filter((Match.user_a_id == user.id) | (Match.user_b_id == user.id))
        .order_by(Match.matched_at.desc())
        .all()
    )
    if not matches:
        return []

    other_ids = {other_user_id(m, user) for m in matches}
    # Une seule requête pour tous les profils plutôt qu'une par match (évite le N+1).
    profiles_by_id = {
        profile.user_id: profile
        for profile in db.query(PublicProfile).filter(PublicProfile.user_id.in_(other_ids)).all()
    }

    results = []
    for match in matches:
        other_id = other_user_id(match, user)
        other_profile = profiles_by_id.get(other_id)
        threshold = match.unlock_threshold or 1
        unlock_pct = min(100, round(match.flame_count / threshold * 100))
        blur_stage = "net" if unlock_pct >= 100 else ("flou_leger" if unlock_pct > 0 else "silhouette")
        results.append(
            {
                "match_id": match.id,
                "other_user_id": other_id,
                "other_display_name": other_profile.display_name if other_profile else "",
                "flame_count": match.flame_count,
                "unlock_threshold": match.unlock_threshold,
                "unlock_pct": unlock_pct,
                "blur_stage": blur_stage,
                "matched_at": match.matched_at,
            }
        )
    return results
