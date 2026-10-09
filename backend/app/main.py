from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1 import (
    admin,
    auth,
    discovery,
    health,
    messaging,
    moderation,
    notifications,
    profiles,
    subscriptions,
)
from app.core.config import get_settings

app = FastAPI(title="Bresonne API", version="0.1.0")

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
app.include_router(admin.router)
app.include_router(notifications.router)

# Tableau de bord staff (interface de revue de modération humaine, C.1/C.2) : HTML/CSS/JS statique
# servi par ce même conteneur, sur /staff — pas /admin, déjà pris par le routeur API ci-dessus.
# Même origine que l'API (pas d'entrée CORS ajoutée pour ce chemin : les appels fetch() du
# tableau de bord vers /admin/* restent same-origin).
app.mount(
    "/staff",
    StaticFiles(directory=Path(__file__).parent / "static" / "admin", html=True),
    name="staff-dashboard",
)


@app.middleware("http")
async def staff_dashboard_security_headers(request, call_next):
    """index.html carries the same CSP via <meta>, but `frame-ancestors` (anti-clickjacking) is
    silently ignored when a CSP is only delivered that way — it only takes effect as a real HTTP
    header, hence this middleware rather than relying on the meta tag alone."""
    response = await call_next(request)
    if request.url.path.startswith("/staff"):
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self'; connect-src 'self'; frame-ancestors 'none'"
        )
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-Content-Type-Options"] = "nosniff"
    return response
