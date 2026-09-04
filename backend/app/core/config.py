from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)

    database_url: str

    jwt_secret: str
    jwt_algorithm: str = "HS256"
    # 15 jours (21 600 min) : rester connecté d'une session à l'autre importe plus pour ce
    # produit qu'une expiration courte façon session bancaire — reconnexion par OTP téléphone
    # (services/otp.py) une fois expiré, jamais un blocage silencieux. Pas de refresh token
    # séparé : un seul JWT longue durée reste le choix le plus simple tant que le produit n'a pas
    # justifié la complexité d'un mécanisme de renouvellement (voir docs/V2_FEATURES.md).
    access_token_expire_minutes: int = 21600
    debug_otp: bool = False
    # Coupe-circuit pour POST /subscriptions/debug-activate (stub gratuit qui accorde le Premium
    # sans paiement, en attendant StoreKit/Play Billing — cahier des charges D.8). Off par défaut,
    # comme debug_otp ci-dessus : sans ce flag, n'importe quel utilisateur authentifié pourrait se
    # l'accorder lui-même si ce backend tournait un jour tel quel en production.
    enable_debug_subscription_endpoint: bool = False

    minio_endpoint: str
    minio_public_endpoint: str
    minio_root_user: str
    minio_root_password: str
    minio_bucket: str
    # Deux réglages distincts, pas un seul : le client interne (minio_endpoint, le nom de service
    # Docker) parle en clair sur le réseau Docker privé même en prod — rien à chiffrer entre deux
    # conteneurs du même hôte. Le client public (minio_public_endpoint, ce qu'un navigateur
    # résout réellement) doit en revanche suivre le vrai schéma externe : http en local, https
    # dès qu'un reverse proxy TLS (Caddy, voir infra/deploy/) se trouve devant lui — sinon les
    # URLs pré-signées générées pointent vers le mauvais schéma et le navigateur les rejette
    # (contenu mixte) ou MinIO refuse la requête (signature calculée pour l'autre schéma).
    minio_secure: bool = False
    minio_public_secure: bool = False

    # Le Flutter web (Phase 6) tourne sur un port différent (localhost:5000) : sans CORS,
    # le navigateur bloque tous les appels vers l'API (localhost:8010).
    cors_origins: str = "http://localhost:5000"

    # Personnalisation de la question du jour (services/question_llm.py) via un modèle Ollama
    # local — gratuit, tourne dans Docker, aucun appel réseau externe. Off par défaut : sans
    # conteneur Ollama démarré (voir docker-compose.yml, service optionnel), inutile de tenter
    # l'appel à chaque fois — le gabarit statique existant reste le comportement par défaut,
    # y compris en CI, qui ne fait jamais tourner ce conteneur.
    ollama_enabled: bool = False
    ollama_base_url: str = "http://ollama:11434"
    ollama_model: str = "llama3.2:1b"
    # Court et strict : un appel de génération bloque la requête HTTP qui crée la question du
    # jour (une seule fois par match/utilisateur/jour, jamais à chaque lecture — voir le
    # commentaire sur DailyQuestion.prompt). Au-delà, on préfère un repli instantané sur le
    # gabarit statique plutôt que de laisser un Ollama lent dégrader ce endpoint.
    ollama_timeout_seconds: float = 3.0

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
