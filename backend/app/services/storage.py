from minio import Minio

from app.core.config import get_settings

settings = get_settings()

_client = Minio(
    settings.minio_endpoint,
    access_key=settings.minio_root_user,
    secret_key=settings.minio_root_password,
    secure=settings.minio_secure,
)


def get_client() -> Minio:
    return _client


def bucket_exists() -> bool:
    return _client.bucket_exists(settings.minio_bucket)
