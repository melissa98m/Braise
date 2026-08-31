"""Filtre de découverte par distance (cahier des charges A.5) — sans géocodage payant ni capture
GPS : l'utilisateur choisit une ville dans une liste fermée de villes françaises
(`data/french_cities.csv`, coordonnées approximatives, suffisantes pour un filtre de distance,
pas un usage cartographique précis), résolue côté serveur une fois au moment de l'enregistrement
du profil (`PublicProfile.city_lat`/`city_lon`, voir `services/profiles.upsert_public_profile`)
plutôt que recalculée à chaque requête de feed.
"""

import csv
import math
from pathlib import Path

DATASET_PATH = Path(__file__).parent / "data" / "french_cities.csv"


def load_cities() -> dict[str, tuple[float, float]]:
    cities: dict[str, tuple[float, float]] = {}
    with DATASET_PATH.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            cities[row["city"]] = (float(row["lat"]), float(row["lon"]))
    return cities


CITIES = load_cities()


def resolve_city(name: str | None) -> tuple[float, float] | None:
    """None si `name` est vide ou ne correspond à aucune ville du jeu de données fermé — un
    profil dans ce cas n'a simplement pas de coordonnées, comme s'il n'avait renseigné aucune
    ville (voir get_feed : un candidat sans coordonnées est exclu d'une recherche filtrée par
    distance, faute de pouvoir vérifier qu'il est dans le rayon)."""
    if not name:
        return None
    return CITIES.get(name)


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Distance à vol d'oiseau entre deux points (latitude, longitude en degrés décimaux)."""
    lat1, lon1 = a
    lat2, lon2 = b
    earth_radius_km = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * earth_radius_km * math.asin(math.sqrt(h))
