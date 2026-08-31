"""Configure Uptime Kuma par l'API plutôt qu'à la main (compte admin + les 3 moniteurs du
cahier des charges D.7/D.11/D.12) — Uptime Kuma n'a pas de format de config déclaratif (voir
CLAUDE.md), mais son client Socket.IO interne est utilisable en dehors de l'UI web via le paquet
`uptime-kuma-api` (pip, gratuit — pas un service tiers, juste un client pour l'API déjà exposée
par le conteneur qu'on fait tourner).

Idempotent : ne recrée pas un moniteur déjà présent (par nom), ne relance pas le setup si un
compte admin existe déjà.

Usage :
    docker compose up -d uptime-kuma
    python3 -m venv /tmp/kuma-venv && /tmp/kuma-venv/bin/pip install uptime-kuma-api
    UPTIME_KUMA_USERNAME=braise UPTIME_KUMA_PASSWORD=<mot de passe fort> \
        /tmp/kuma-venv/bin/python infra/uptime-kuma/setup.py

    # Pour configurer aussi l'alerte webhook (Discord/Slack/générique) au même moment :
    UPTIME_KUMA_USERNAME=braise UPTIME_KUMA_PASSWORD=<...> \
        UPTIME_KUMA_WEBHOOK_URL=https://discord.com/api/webhooks/... \
        UPTIME_KUMA_WEBHOOK_KIND=discord \
        /tmp/kuma-venv/bin/python infra/uptime-kuma/setup.py

`UPTIME_KUMA_WEBHOOK_KIND` : `discord`, `slack`, ou `generic` (webhook JSON brut, pour n'importe
quel autre récepteur). Aucun webhook n'est configuré si `UPTIME_KUMA_WEBHOOK_URL` est absent —
les moniteurs et le compte admin sont créés quand même, l'alerte reste à ajouter plus tard.
"""

import os
import sys

from uptime_kuma_api import MonitorType, NotificationType, UptimeKumaApi

URL = os.environ.get("UPTIME_KUMA_URL", "http://localhost:8082")
USERNAME = os.environ.get("UPTIME_KUMA_USERNAME")
PASSWORD = os.environ.get("UPTIME_KUMA_PASSWORD")
WEBHOOK_URL = os.environ.get("UPTIME_KUMA_WEBHOOK_URL")
WEBHOOK_KIND = os.environ.get("UPTIME_KUMA_WEBHOOK_KIND", "generic")

MONITORS = [
    dict(
        type=MonitorType.HTTP,
        name="Backend (health)",
        url="http://backend:8000/health",
        interval=60,
        retryInterval=60,
        maxretries=3,
    ),
    dict(
        type=MonitorType.HTTP,
        name="MinIO (health)",
        url="http://minio:9000/minio/health/live",
        interval=60,
        retryInterval=60,
        maxretries=3,
    ),
    dict(
        type=MonitorType.PORT,
        name="Postgres (TCP)",
        hostname="db",
        port=5432,
        interval=60,
        retryInterval=60,
        maxretries=3,
    ),
]


def main() -> None:
    if not USERNAME or not PASSWORD:
        sys.exit(
            "UPTIME_KUMA_USERNAME et UPTIME_KUMA_PASSWORD sont requis (voir la docstring de ce "
            "fichier pour l'usage)."
        )

    api = UptimeKumaApi(URL)
    try:
        if api.need_setup():
            print("Création du compte admin...")
            api.setup(USERNAME, PASSWORD)
        api.login(USERNAME, PASSWORD)

        existing_monitors = {m["name"] for m in api.get_monitors()}
        for monitor in MONITORS:
            if monitor["name"] in existing_monitors:
                print(f"Moniteur déjà présent : {monitor['name']}")
                continue
            api.add_monitor(**monitor)
            print(f"Moniteur ajouté : {monitor['name']}")

        if WEBHOOK_URL:
            existing_notifications = {n["name"] for n in api.get_notifications()}
            notif_name = "Alerte panne"
            if notif_name in existing_notifications:
                print(f"Notification déjà présente : {notif_name}")
            else:
                if WEBHOOK_KIND == "discord":
                    api.add_notification(
                        name=notif_name,
                        isDefault=True,
                        applyExisting=True,
                        type=NotificationType.DISCORD,
                        discordWebhookUrl=WEBHOOK_URL,
                        discordUsername="Braise — supervision",
                    )
                elif WEBHOOK_KIND == "slack":
                    api.add_notification(
                        name=notif_name,
                        isDefault=True,
                        applyExisting=True,
                        type=NotificationType.SLACK,
                        slackwebhookURL=WEBHOOK_URL,
                    )
                else:
                    api.add_notification(
                        name=notif_name,
                        isDefault=True,
                        applyExisting=True,
                        type=NotificationType.WEBHOOK,
                        webhookURL=WEBHOOK_URL,
                        webhookContentType="json",
                    )
                print(f"Notification ajoutée : {notif_name} ({WEBHOOK_KIND})")
        else:
            print(
                "UPTIME_KUMA_WEBHOOK_URL absent : moniteurs et compte admin créés, mais aucune "
                "alerte configurée — à ajouter plus tard depuis le dashboard ou en relançant ce "
                "script avec la variable renseignée."
            )
    finally:
        api.disconnect()

    print("Terminé.")


if __name__ == "__main__":
    main()
