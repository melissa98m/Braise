from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)

    database_url: str

    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    debug_otp: bool = False

    minio_endpoint: str
    minio_public_endpoint: str
    minio_root_user: str
    minio_root_password: str
    minio_bucket: str
    minio_secure: bool = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
