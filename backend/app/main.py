from fastapi import FastAPI

from app.api.v1 import auth, discovery, health, messaging, moderation, profiles, subscriptions

app = FastAPI(title="Braise API", version="0.1.0")

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(profiles.router)
app.include_router(discovery.router)
app.include_router(messaging.router)
app.include_router(moderation.router)
app.include_router(subscriptions.router)
