from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import auth, discovery, health, messaging, moderation, profiles, subscriptions
from app.core.config import get_settings

app = FastAPI(title="Braise API", version="0.1.0")

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(profiles.router)
app.include_router(discovery.router)
app.include_router(messaging.router)
app.include_router(moderation.router)
app.include_router(subscriptions.router)
