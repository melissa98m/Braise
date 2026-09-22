import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.profile import (
    AvatarSpec,
    PartnerProfileOut,
    PrivateProfileOut,
    PublicProfileIn,
    PublicProfileOut,
)
from app.services import profiles as profiles_service
from app.services.geo import CITIES, nearest_city

router = APIRouter(prefix="/profiles", tags=["profiles"])


@router.get("/cities", response_model=list[str])
def list_cities():
    # Référence statique (services/geo.py), aucune donnée utilisateur : pas besoin
    # d'authentification, contrairement au reste de ce routeur — sert à peupler le sélecteur de
    # ville mobile (P9.3) avec exactement les noms que `city` peut résoudre en coordonnées.
    return sorted(CITIES)


@router.get("/cities/nearest", response_model=str)
def get_nearest_city(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    user: User = Depends(get_current_user),
):
    # Authentifié (contrairement à /cities) : reçoit une vraie position GPS ponctuelle
    # transmise par le client (voir mobile/lib/location/), pas juste une donnée de référence
    # statique — pas de raison de l'exposer sans compte. Gratuit : aucun service de géocodage
    # tiers, juste un min() sur la liste fermée déjà embarquée (services/geo.nearest_city).
    city = nearest_city(lat, lon)
    if city is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aucune ville de référence disponible.")
    return city


@router.get("/me/public", response_model=PublicProfileOut)
def get_my_public_profile(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    profile = profiles_service.get_or_create_public_profile(db, user)
    return profiles_service.to_public_profile_out(db, profile, user.is_verified)


@router.put("/me/public", response_model=PublicProfileOut)
def update_my_public_profile(
    payload: PublicProfileIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = profiles_service.upsert_public_profile(db, user, payload)
    return profiles_service.to_public_profile_out(db, profile, user.is_verified)


@router.post("/me/avatar/regenerate", response_model=AvatarSpec)
def regenerate_my_avatar(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    return profiles_service.regenerate_avatar(db, user)


@router.get("/me/private", response_model=PrivateProfileOut)
def get_my_private_profile(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    profile = profiles_service.get_or_create_private_profile(db, user)
    return profiles_service.to_private_profile_out(profile)


@router.post("/me/private/photos", response_model=PrivateProfileOut)
async def upload_my_private_photo(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = await profiles_service.add_private_photo(db, user, file)
    return profiles_service.to_private_profile_out(profile)


@router.delete("/me/private/photos/{object_key:path}", response_model=PrivateProfileOut)
def delete_my_private_photo(
    object_key: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = profiles_service.remove_private_photo(db, user, object_key)
    return profiles_service.to_private_profile_out(profile)


@router.get("/matches/{match_id}/partner-photos", response_model=PrivateProfileOut)
def get_partner_photos(
    match_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return profiles_service.get_partner_photos(db, user, match_id)


@router.get("/matches/{match_id}/partner-profile", response_model=PartnerProfileOut)
def get_partner_profile(
    match_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return profiles_service.get_partner_profile(db, user, match_id)
