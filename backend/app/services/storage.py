from datetime import timedelta
from io import BytesIO

from minio import Minio

from app.core.config import get_settings

settings = get_settings()

# Client interne : parle au conteneur minio via le réseau Docker (upload, delete, bucket check).
_client = Minio(
    settings.minio_endpoint,
    access_key=settings.minio_root_user,
    secret_key=settings.minio_root_password,
    secure=settings.minio_secure,
    region="us-east-1",
)

# Client "public" : sert uniquement à signer des URLs que le navigateur/l'app mobile peut
# réellement résoudre (host:port accessible depuis l'extérieur du réseau Docker), pas le nom
# de service interne "minio". Mêmes identifiants, seul l'hôte annoncé dans l'URL change.
# region fixée explicitement : sans elle, minio-py fait un aller-retour réseau vers
# minio_public_endpoint pour déterminer la région du bucket avant de signer — un aller-retour
# qui échoue quand ce code tourne dans le conteneur backend (où "localhost" ne pointe pas vers
# minio). Un presigned URL n'a de toute façon jamais besoin d'appeler le serveur.
_public_client = Minio(
    settings.minio_public_endpoint,
    access_key=settings.minio_root_user,
    secret_key=settings.minio_root_password,
    secure=settings.minio_secure,
    region="us-east-1",
)


def get_client() -> Minio:
    return _client


def bucket_exists() -> bool:
    return _client.bucket_exists(settings.minio_bucket)


def upload_private_photo(object_key: str, data: bytes, content_type: str) -> None:
    _client.put_object(
        settings.minio_bucket,
        object_key,
        BytesIO(data),
        length=len(data),
        content_type=content_type,
    )


def delete_object(object_key: str) -> None:
    _client.remove_object(settings.minio_bucket, object_key)


def presigned_get_url(object_key: str, expires_minutes: int = 10) -> str:
    return _public_client.presigned_get_object(
        settings.minio_bucket, object_key, expires=timedelta(minutes=expires_minutes)
    )
