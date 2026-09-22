import uuid
from collections import defaultdict

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.match import Match
from app.models.message import Message
from app.models.profile import PublicProfile
from app.models.swipe import Swipe, SwipeDecision
from app.models.user import User
from app.services.avatar import avatar_spec_from_seed
from app.services.geo import haversine_km
from app.services.matches import other_user_id
from app.services.moderation import compute_trust_scores_batch
from app.services.profiles import compute_age
from app.services.subscriptions import can_create_new_match, is_premium

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


def _candidate_dict(
    profile: PublicProfile,
    my_interests: list[str],
    verified_by_id: dict,
    trust_by_id: dict,
) -> dict:
    """Factorisé entre `get_feed` et `get_likes_received` : même forme de carte candidat des deux
    côtés (compatibilité, badge vérifié, score de confiance), pas de copie divergente."""
    return {
        "user_id": profile.user_id,
        "display_name": profile.display_name,
        "age": compute_age(profile.birth_date),
        "bio": profile.bio,
        "interests": profile.interests,
        "avatar": avatar_spec_from_seed(profile.avatar_seed),
        "common_interests": sorted(set(my_interests) & set(profile.interests)),
        "compatibility_score": round(_jaccard(my_interests, profile.interests), 2),
        "is_verified": verified_by_id.get(profile.user_id, False),
        "trust_score": trust_by_id[profile.user_id]["score"],
        "trust_label": trust_by_id[profile.user_id]["label"],
    }


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
    if my_profile is not None and my_profile.looking_for_gender:
        query = query.filter(PublicProfile.gender.in_(my_profile.looking_for_gender))

    candidates = query.order_by(PublicProfile.updated_at.desc()).limit(MAX_CANDIDATE_POOL).all()

    age_min = my_profile.age_min if my_profile else None
    age_max = my_profile.age_max if my_profile else None
    # Distance (P9.3) : opt-in comme l'âge/le genre — sans `max_distance_km` renseigné, aucun
    # filtrage. Avec, un candidat sans ville résolue (jamais renseignée, ou hors de la liste
    # fermée de services/geo.py) est exclu : impossible de vérifier qu'il est dans le rayon.
    my_location = (
        (my_profile.city_lat, my_profile.city_lon)
        if my_profile and my_profile.city_lat is not None and my_profile.city_lon is not None
        else None
    )
    max_distance_km = my_profile.max_distance_km if my_profile else None

    # Batché en une requête IN(...) plutôt qu'un aller-retour par candidat — même règle que
    # list_my_matches (services/matches, cf. CLAUDE.md) pour éviter un N+1.
    candidate_ids = [profile.user_id for profile in candidates]
    verified_by_id = dict(db.query(User.id, User.is_verified).filter(User.id.in_(candidate_ids)))
    trust_by_id = compute_trust_scores_batch(db, candidate_ids)

    scored = []
    for profile in candidates:
        age = compute_age(profile.birth_date)
        if age_min is not None and age < age_min:
            continue
        if age_max is not None and age > age_max:
            continue
        if max_distance_km is not None:
            if my_location is None or profile.city_lat is None or profile.city_lon is None:
                continue
            distance_km = haversine_km(my_location, (profile.city_lat, profile.city_lon))
            if distance_km > max_distance_km:
                continue
        scored.append(_candidate_dict(profile, my_interests, verified_by_id, trust_by_id))

    scored.sort(key=lambda item: item["compatibility_score"], reverse=True)
    return scored[:limit]


def get_likes_received(db: Session, user: User) -> dict:
    """« Qui vous a déjà braisé » — moteur d'engagement/conversion classique (cahier des charges
    hors périmètre explicite, ajouté à la demande) : les profils qui m'ont déjà liké et que je
    n'ai pas encore swipés moi-même (dans un sens ou l'autre — une fois swipé, `already_swiped`
    les exclut déjà partout ailleurs, pas de raison de les garder ici). Le compte est toujours
    renvoyé (gratuit) ; le détail des profils est réservé à Bresonne+ — c'est la vraie raison de
    vouloir l'abonnement au-delà de la limite de matchs (`can_create_new_match`)."""
    my_profile = db.get(PublicProfile, user.id)
    my_interests = my_profile.interests if my_profile else []

    already_swiped = select(Swipe.to_user_id).where(Swipe.from_user_id == user.id)
    likers_query = (
        db.query(PublicProfile)
        .join(Swipe, Swipe.from_user_id == PublicProfile.user_id)
        .filter(
            Swipe.to_user_id == user.id,
            Swipe.decision == SwipeDecision.LIKE.value,
            PublicProfile.is_published.is_(True),
            PublicProfile.user_id.notin_(already_swiped),
        )
    )
    count = likers_query.count()

    if not is_premium(db, user.id):
        return {"count": count, "is_premium": False, "candidates": []}

    likers = likers_query.order_by(PublicProfile.updated_at.desc()).limit(MAX_CANDIDATE_POOL).all()
    candidate_ids = [profile.user_id for profile in likers]
    verified_by_id = dict(db.query(User.id, User.is_verified).filter(User.id.in_(candidate_ids)))
    trust_by_id = compute_trust_scores_batch(db, candidate_ids)

    candidates = [
        _candidate_dict(profile, my_interests, verified_by_id, trust_by_id) for profile in likers
    ]
    candidates.sort(key=lambda item: item["compatibility_score"], reverse=True)
    return {"count": count, "is_premium": True, "candidates": candidates}


def record_swipe(
    db: Session, user: User, to_user_id: uuid.UUID, decision: SwipeDecision
) -> bool:
    if to_user_id == user.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Impossible de se swiper soi-même.")

    if decision == SwipeDecision.LIKE and not can_create_new_match(db, user):
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            "Limite de matchs gratuits atteinte. Passez à Bresonne+ pour continuer à liker.",
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

    # Idem pour le compte de messages non lus (badge P9.2) : une seule requête sur tous les
    # matchs plutôt qu'une par match. Le seuil "lu jusqu'à" diffère par match (mon côté du
    # match, `last_read_at_a` ou `last_read_at_b` selon lequel je suis) donc le filtre par date
    # se fait ici en Python plutôt qu'en SQL — même principe que le tri par compatibilité du feed
    # (services/discovery.get_feed) : borné par match plutôt que par un JOIN corrélé par ligne.
    match_ids = [m.id for m in matches]
    messages_from_other_side = defaultdict(list)
    for match_id, sender_id, created_at in db.query(
        Message.match_id, Message.sender_id, Message.created_at
    ).filter(Message.match_id.in_(match_ids), Message.sender_id != user.id):
        messages_from_other_side[match_id].append(created_at)

    results = []
    for match in matches:
        other_id = other_user_id(match, user)
        other_profile = profiles_by_id.get(other_id)
        threshold = match.unlock_threshold or 1
        unlock_pct = min(100, round(match.flame_count / threshold * 100))
        blur_stage = "net" if unlock_pct >= 100 else ("flou_leger" if unlock_pct > 0 else "silhouette")
        my_last_read = match.last_read_at_a if match.user_a_id == user.id else match.last_read_at_b
        unread_count = sum(
            1
            for created_at in messages_from_other_side.get(match.id, [])
            if my_last_read is None or created_at > my_last_read
        )
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
                "unread_count": unread_count,
            }
        )
    return results
