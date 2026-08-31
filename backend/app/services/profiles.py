import uuid
from datetime import date, datetime, timezone

from fastapi import HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.models.photo_access_log import PhotoAccessLog
from app.models.profile import PrivateProfile, PublicProfile
from app.models.user import User
from app.schemas.profile import PublicProfileIn
from app.services import storage
from app.services.avatar import avatar_spec_from_seed, generate_avatar_seed
from app.services.matches import get_match_or_404, other_user_id
from app.services.subscriptions import is_premium

ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
MAX_PHOTOS = 3
MAX_PHOTO_BYTES = 8 * 1024 * 1024


def compute_age(birth_date: date) -> int:
    today = date.today()
    return today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))


def get_or_create_public_profile(db: Session, user: User) -> PublicProfile:
    profile = db.get(PublicProfile, user.id)
    if profile is None:
        profile = PublicProfile(
            user_id=user.id,
            display_name="",
            birth_date=date(2000, 1, 1),
            bio="",
            interests=[],
            avatar_seed=generate_avatar_seed(),
            is_published=False,
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


def upsert_public_profile(db: Session, user: User, data: PublicProfileIn) -> PublicProfile:
    profile = get_or_create_public_profile(db, user)
    profile.display_name = data.display_name
    profile.birth_date = data.birth_date
    profile.bio = data.bio
    profile.interests = data.interests
    profile.is_published = data.is_published
    profile.gender = data.gender
    profile.looking_for_gender = data.looking_for_gender
    profile.age_min = data.age_min
    profile.age_max = data.age_max
    profile.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(profile)
    return profile


def regenerate_avatar(db: Session, user: User) -> dict:
    profile = get_or_create_public_profile(db, user)
    profile.avatar_seed = generate_avatar_seed()
    db.commit()
    db.refresh(profile)
    return avatar_spec_from_seed(profile.avatar_seed)


def to_public_profile_out(db: Session, profile: PublicProfile) -> dict:
    return {
        "display_name": profile.display_name,
        "age": compute_age(profile.birth_date),
        "bio": profile.bio,
        "interests": profile.interests,
        "avatar": avatar_spec_from_seed(profile.avatar_seed),
        "is_published": profile.is_published,
        "is_premium": is_premium(db, profile.user_id),
        "gender": profile.gender,
        "looking_for_gender": profile.looking_for_gender,
        "age_min": profile.age_min,
        "age_max": profile.age_max,
    }


def get_or_create_private_profile(db: Session, user: User) -> PrivateProfile:
    profile = db.get(PrivateProfile, user.id)
    if profile is None:
        profile = PrivateProfile(user_id=user.id, photo_keys=[])
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


async def add_private_photo(db: Session, user: User, upload: UploadFile) -> PrivateProfile:
    profile = get_or_create_private_profile(db, user)
    if len(profile.photo_keys) >= MAX_PHOTOS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Maximum 3 photos dans le profil privé."
        )
    if upload.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Format d'image non supporté.")

    data = await upload.read()
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Photo trop volumineuse (8 Mo max).")

    ext = ALLOWED_IMAGE_TYPES[upload.content_type]
    object_key = f"private/{user.id}/{uuid.uuid4().hex}.{ext}"
    storage.upload_private_photo(object_key, data, upload.content_type)

    profile.photo_keys = [*profile.photo_keys, object_key]
    db.commit()
    db.refresh(profile)
    return profile


def remove_private_photo(db: Session, user: User, object_key: str) -> PrivateProfile:
    profile = get_or_create_private_profile(db, user)
    if object_key not in profile.photo_keys:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo introuvable.")

    storage.delete_object(object_key)
    profile.photo_keys = [key for key in profile.photo_keys if key != object_key]
    db.commit()
    db.refresh(profile)
    return profile


def to_private_profile_out(profile: PrivateProfile) -> dict:
    return {
        "photos": [
            {"key": key, "url": storage.presigned_get_url(key)} for key in profile.photo_keys
        ]
    }


def get_partner_photos(db: Session, user: User, match_id: uuid.UUID) -> dict:
    match = get_match_or_404(db, user, match_id)
    if match.unlocked_at is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Le profil privé n'est pas encore débloqué pour ce match."
        )

    partner_id = other_user_id(match, user)
    partner_profile = db.get(PrivateProfile, partner_id)
    photos = partner_profile.photo_keys if partner_profile else []

    # Journal d'audit : uniquement l'accès aux photos d'*autrui* (cahier des charges A.9) — voir
    # get_or_create_private_profile / to_private_profile_out pour la consultation de ses propres
    # photos, qui n'a pas besoin d'être journalisée.
    db.add(PhotoAccessLog(match_id=match_id, viewer_id=user.id, owner_id=partner_id))
    db.commit()

    return {"photos": [{"key": key, "url": storage.presigned_get_url(key)} for key in photos]}
