from app.services.storage import bucket_exists


def test_minio_bucket_ready():
    assert bucket_exists() is True
