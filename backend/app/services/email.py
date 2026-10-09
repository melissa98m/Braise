import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import make_msgid

from app.core.config import get_settings

logger = logging.getLogger(__name__)

SMTP_TIMEOUT_SECONDS = 10


def _otp_message(to: str, code: str, ttl_minutes: int) -> EmailMessage:
    settings = get_settings()
    message = EmailMessage()
    message["Subject"] = f"{code} est votre code de connexion Bresonne"
    message["From"] = settings.email_from
    message["To"] = to
    message["Message-ID"] = make_msgid(domain=settings.email_from.rsplit("@", 1)[-1].strip("> "))
    # Aucun lien cliquable, à dessein : un code à recopier ne ressemble pas à un email de
    # phishing, et ne donne rien à un tiers qui ouvrirait le message sans avoir l'app ouverte.
    text = (
        f"Votre code de connexion Bresonne : {code}\n\n"
        f"Il est valable {ttl_minutes} minutes et ne peut servir qu'une fois.\n\n"
        "Si vous n'avez pas demandé ce code, ignorez simplement ce message : personne ne peut "
        "se connecter à votre compte sans lui.\n\n"
        "— L'équipe Bresonne"
    )
    message.set_content(text)
    message.add_alternative(
        f"""<!doctype html>
<html lang="fr"><body style="font-family:system-ui,sans-serif;color:#1c1917;line-height:1.5">
<p>Votre code de connexion Bresonne :</p>
<p style="font-size:28px;font-weight:700;letter-spacing:6px;margin:16px 0">{code}</p>
<p>Il est valable {ttl_minutes} minutes et ne peut servir qu'une fois.</p>
<p style="color:#57534e">Si vous n'avez pas demandé ce code, ignorez simplement ce message :
personne ne peut se connecter à votre compte sans lui.</p>
<p style="color:#57534e">— L'équipe Bresonne</p>
</body></html>""",
        subtype="html",
    )
    return message


def _send_smtp(message: EmailMessage) -> None:
    settings = get_settings()
    context = ssl.create_default_context()
    if settings.smtp_security == "ssl":
        server = smtplib.SMTP_SSL(
            settings.smtp_host, settings.smtp_port, timeout=SMTP_TIMEOUT_SECONDS, context=context
        )
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=SMTP_TIMEOUT_SECONDS)
    with server:
        if settings.smtp_security == "starttls":
            server.starttls(context=context)
        if settings.smtp_username:
            server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(message)


def send_otp_email(to: str, code: str, ttl_minutes: int) -> None:
    """Envoie le code OTP. Appelé en tâche de fond (api/v1/auth.py), jamais dans la requête.

    Ne lève jamais vers l'appelant : la réponse HTTP est déjà partie, et elle doit rester
    identique que l'envoi réussisse ou non (pas d'énumération d'adresses via un code d'erreur).
    Un échec est journalisé — sans le code, qui ne doit apparaître dans les logs qu'en mode
    `console` (dev), jamais quand un vrai email part.
    """
    settings = get_settings()
    if settings.email_backend == "console":
        logger.warning("[EMAIL console] code OTP pour %s : %s", to, code)
        return
    try:
        _send_smtp(_otp_message(to, code, ttl_minutes))
    except (smtplib.SMTPException, OSError):
        logger.exception("Échec d'envoi du code OTP par email à %s", to)
