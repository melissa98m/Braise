import uuid
from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

from app.models.client_error import ClientError
from app.models.feedback import Feedback
from app.models.match import Match
from app.models.message import Message
from app.models.profile import PrivateProfile, PublicProfile
from app.models.rating import Rating
from app.models.report import Report
from app.models.user import User
from app.models.user_activity import UserActivity
from app.services import notifications as notifications_service
from app.services import otp as otp_service
from app.services import storage
from app.services.matches import other_user_id

# Placeholder utilisé partout où un profil "vidé" a besoin d'une birth_date non nulle — même
# valeur que get_or_create_public_profile pour un profil jamais rempli (voir services/profiles.py).
_UNSET_BIRTH_DATE = date(2000, 1, 1)


def export_my_data(db: Session, user: User) -> dict:
    """Droit à la portabilité (cahier des charges A.9) : un export JSON de tout ce que ce compte
    a produit sur la plateforme. Ne contient pas les octets des photos, seulement leurs clés —
    exporter le contenu binaire n'apporte rien à l'utilisateur au-delà de ce que
    /profiles/me/private lui donne déjà à la demande.
    """
    public_profile = db.get(PublicProfile, user.id)
    private_profile = db.get(PrivateProfile, user.id)

    matches = (
        db.query(Match).filter((Match.user_a_id == user.id) | (Match.user_b_id == user.id)).all()
    )
    match_ids = [m.id for m in matches]

    messages = (
        db.query(Message).filter(Message.match_id.in_(match_ids)).order_by(Message.created_at)
        if match_ids
        else []
    )
    ratings_given = db.query(Rating).filter(Rating.rater_id == user.id).all()
    ratings_received = db.query(Rating).filter(Rating.ratee_id == user.id).all()
    reports_filed = db.query(Report).filter(Report.reporter_id == user.id).all()
    feedback_sent = db.query(Feedback).filter(Feedback.user_id == user.id).all()
    active_days = (
        db.query(UserActivity.day).filter(UserActivity.user_id == user.id).order_by(UserActivity.day)
    )

    return {
        "account": {
            "id": str(user.id),
            "email": user.email,
            "is_verified": user.is_verified,
            "created_at": user.created_at.isoformat(),
            "consents": {
                "age_confirmed_at": (
                    user.consent_age_at.isoformat() if user.consent_age_at else None
                ),
                "cgu_accepted_at": (
                    user.consent_cgu_at.isoformat() if user.consent_cgu_at else None
                ),
                "privacy_acknowledged_at": (
                    user.consent_privacy_at.isoformat() if user.consent_privacy_at else None
                ),
                "sensitive_data_consented_at": (
                    user.consent_sensitive_data_at.isoformat()
                    if user.consent_sensitive_data_at
                    else None
                ),
            },
        },
        "public_profile": (
            {
                "display_name": public_profile.display_name,
                "bio": public_profile.bio,
                "interests": public_profile.interests,
                "is_published": public_profile.is_published,
            }
            if public_profile
            else None
        ),
        "private_profile": (
            {"photo_keys": private_profile.photo_keys} if private_profile else None
        ),
        "matches": [
            {
                "match_id": str(m.id),
                "other_user_id": str(other_user_id(m, user)),
                "matched_at": m.matched_at.isoformat(),
                "flame_count": m.flame_count,
                "unlocked_at": m.unlocked_at.isoformat() if m.unlocked_at else None,
            }
            for m in matches
        ],
        "messages_sent": [
            {"match_id": str(msg.match_id), "body": msg.body, "created_at": msg.created_at.isoformat()}
            for msg in messages
            if msg.sender_id == user.id
        ],
        "ratings_given": [
            {"match_id": str(r.match_id), "score": r.score, "comment": r.comment}
            for r in ratings_given
        ],
        "ratings_received": [
            {"score": r.score, "comment": r.comment, "suspected_rancor": r.suspected_rancor}
            for r in ratings_received
        ],
        "reports_filed": [
            {"reason": r.reason, "status": r.status, "created_at": r.created_at.isoformat()}
            for r in reports_filed
        ],
        "feedback_sent": [
            {"category": f.category, "message": f.message, "created_at": f.created_at.isoformat()}
            for f in feedback_sent
        ],
        "active_days": [day.isoformat() for (day,) in active_days],
    }


def delete_my_account(db: Session, user: User) -> None:
    """Droit à l'oubli (cahier des charges A.9) : anonymisation, pas un hard-delete cascadé — les
    Match/Rating d'un tiers restent intacts, seul le contenu qui *identifie ce compte* est scrubé.
    """
    private_profile = db.get(PrivateProfile, user.id)
    if private_profile is not None:
        for object_key in private_profile.photo_keys:
            storage.delete_object(object_key)
        private_profile.photo_keys = []

    public_profile = db.get(PublicProfile, user.id)
    if public_profile is not None:
        public_profile.display_name = ""
        public_profile.bio = ""
        public_profile.interests = []
        public_profile.birth_date = _UNSET_BIRTH_DATE
        public_profile.is_published = False

    # Les messages restent lisibles par l'autre participant (c'est aussi sa conversation), mais
    # leur contenu ne doit plus être attribuable à ce compte après suppression.
    db.query(Message).filter(Message.sender_id == user.id).update(
        {"body": "[message supprimé]"}
    )

    # Un abonnement push oublié survivrait à la suppression du compte et continuerait de recevoir
    # des notifications tant qu'il n'est pas détecté mort côté service de push (404/410) — la même
    # ligne de raisonnement que la purge des photos privées ci-dessus, pas une donnée à laisser
    # orpheline.
    notifications_service.delete_all_subscriptions_for_user(db, user.id)

    # Retours (texte libre, peut contenir n'importe quoi) et jours d'activité : supprimés, pas
    # anonymisés — ils ne portent les droits de personne d'autre, contrairement aux messages.
    # Une erreur remontée par l'app reste (utile au produit) mais n'est plus rattachée à ce compte.
    db.query(Feedback).filter(Feedback.user_id == user.id).delete()
    db.query(UserActivity).filter(UserActivity.user_id == user.id).delete()
    db.query(ClientError).filter(ClientError.last_user_id == user.id).update({"last_user_id": None})

    now = datetime.now(timezone.utc)
    otp_service.delete_challenge(db, user.email)
    # Domaine réservé `.invalid` (RFC 2606) : refusé par la validation des schémas d'auth, donc ce
    # tombstone ne pourra jamais redevenir une adresse de connexion, et ne libère pas pour autant
    # l'adresse d'origine d'un historique rattaché — elle est simplement réutilisable pour un
    # nouveau compte vierge.
    user.email = f"deleted-{uuid.uuid4().hex}@deleted.invalid"
    user.deleted_at = now

    db.commit()
