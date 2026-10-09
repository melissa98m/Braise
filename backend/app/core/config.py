from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Fragments qui trahissent une valeur d'exemple recopiée telle quelle depuis .env.example /
# .env.prod.example — voir `_refuse_unsafe_config_outside_development` ci-dessous.
_PLACEHOLDER_MARKERS = ("change_me", "changeme", "example.com")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)

    # `development` (poste de dev, CI), `beta` (VPS de bêta fermée joignable par de vrais
    # testeurs), `production`. Hors `development`, le backend refuse de démarrer sur une
    # configuration dangereuse (code OTP renvoyé dans la réponse, secret d'exemple...) plutôt que
    # de compter sur une checklist de déploiement relue à la main — voir le validateur en bas de
    # cette classe. `beta` diffère de `production` sur un seul point, volontairement : l'endpoint
    # Premium de debug y reste autorisé, pour que les testeurs puissent essayer le Premium sans
    # vrai paiement (aucune intégration StoreKit/Play Billing n'existe encore).
    environment: Literal["development", "beta", "production"] = "development"

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
    # Jamais utilisé par le backend lui-même (c'est MinIO qui chiffre, voir storage.py) — lu ici
    # uniquement pour que le validateur hors développement refuse une clé d'exemple.
    minio_kms_secret_key: str = ""
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

    # Pub/sub partagé entre instances backend pour la messagerie WebSocket (cahier des charges
    # D.4, docs/V2_FEATURES.md §3) — sans ça, deux utilisateurs connectés à deux instances
    # différentes ne se voient plus. Gratuit/local (redis:7-alpine, docker-compose.yml), aucune
    # donnée n'y est durablement stockée (voir docs/DPIA.md) : seul le relais pub/sub est utilisé.
    redis_url: str = "redis://redis:6379/0"

    # Notifications push réelles (Web Push standard + VAPID, RFC 8291/8292) — remplace P9.1
    # (notifications navigateur premier-plan uniquement), voir docs/V2_FEATURES.md §6. Off par
    # défaut, même garde-fou que ollama_enabled ci-dessus : sans PUSH_ENABLED=true, aucun appel
    # réseau vers un service de push de navigateur n'est jamais tenté, y compris en CI. Aucun
    # service tiers payant : le service de push est celui déjà intégré au navigateur de la
    # personne (inhérent au standard Web Push), pas une dépendance opérationnelle de ce projet —
    # cohérent avec la contrainte "pas de Firebase" du cahier des charges.
    push_enabled: bool = False
    vapid_private_key: str
    vapid_public_key: str
    # Exigé par la RFC 8292 (contact joignable en cas de souci côté service de push) — une vraie
    # adresse en prod, jamais une valeur bidon.
    vapid_subject: str = "mailto:CHANGE_ME@example.com"

    # Envoi du code OTP par email (services/email.py). `console` (défaut, dev/CI) : le code part
    # seulement dans les logs du backend — jamais un vrai envoi. `smtp` : vrai envoi, Resend en
    # prod (smtp.resend.com:465, identifiant "resend", mot de passe = clé API Resend) ou Mailpit
    # en local (profil Compose "mail", mailpit:1025, sans chiffrement ni authentification). Du
    # SMTP standard plutôt que le SDK Resend : changer de fournisseur ne touche que ces variables.
    email_backend: Literal["console", "smtp"] = "console"
    smtp_host: str = ""
    smtp_port: int = 465
    # `ssl` : TLS dès la connexion (port 465, Resend). `starttls` : connexion en clair puis
    # montée en TLS (port 587). `none` : aucun chiffrement — uniquement pour Mailpit en local,
    # refusé hors développement par le validateur ci-dessous.
    smtp_security: Literal["ssl", "starttls", "none"] = "ssl"
    smtp_username: str = ""
    smtp_password: str = ""
    email_from: str = "Bresonne <no-reply@example.com>"

    # Plafond de demandes de code OTP par adresse IP et par heure (services/otp.py), en plus des
    # limites par email. 0 désactive ce plafond : nécessaire en dev/CI, où la suite de tests et
    # les scripts de seed/de charge créent des centaines de comptes depuis la même IP.
    otp_requests_per_ip_per_hour: int = 20

    @property
    def is_development(self) -> bool:
        return self.environment == "development"

    @model_validator(mode="after")
    def _refuse_unsafe_config_outside_development(self) -> "Settings":
        if self.is_development:
            return self
        problems: list[str] = []
        if self.debug_otp:
            problems.append("DEBUG_OTP=true renverrait le code OTP dans la réponse de l'API")
        if self.environment == "production" and self.enable_debug_subscription_endpoint:
            problems.append("ENABLE_DEBUG_SUBSCRIPTION_ENDPOINT=true accorderait le Premium sans paiement")
        if self.email_backend != "smtp":
            problems.append("EMAIL_BACKEND doit valoir smtp (aucun code ne serait jamais envoyé)")
        if self.email_backend == "smtp" and self.smtp_security == "none":
            problems.append("SMTP_SECURITY=none enverrait les codes OTP en clair")
        if len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET doit faire au moins 32 caractères")
        secrets_to_check = {
            "JWT_SECRET": self.jwt_secret,
            "MINIO_KMS_SECRET_KEY": self.minio_kms_secret_key,
            "MINIO_ROOT_PASSWORD": self.minio_root_password,
            "SMTP_PASSWORD": self.smtp_password,
            "EMAIL_FROM": self.email_from,
        }
        if self.push_enabled:
            secrets_to_check["VAPID_PRIVATE_KEY"] = self.vapid_private_key
            secrets_to_check["VAPID_SUBJECT"] = self.vapid_subject
        for name, value in secrets_to_check.items():
            if not value or any(marker in value.lower() for marker in _PLACEHOLDER_MARKERS):
                problems.append(f"{name} est vide ou encore une valeur d'exemple")
        if problems:
            raise ValueError(
                f"Configuration refusée pour ENVIRONMENT={self.environment} : " + " ; ".join(problems)
            )
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
