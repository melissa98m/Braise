import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Un seul client réutilisé (pool de connexions HTTP garde la connexion à Ollama ouverte entre
# deux générations) plutôt qu'un nouveau client par appel — cet appel est sur le chemin critique
# de la création de la question du jour (voir services/messaging.py), donc chaque milliseconde
# évitable compte.
_client = httpx.Client()

# Une instruction par catégorie de quiz (voir services/messaging.py._eligible_categories) — la
# phrase générée doit correspondre à ce que les options proposent réellement, jamais un texte
# générique qui ne dirait pas sur quoi porte le choix.
_INSTRUCTIONS = {
    "interest": (
        "Tu es un générateur de questions de quiz pour une app de rencontre. Écris EXACTEMENT une "
        "phrase interrogative en français (elle doit se terminer par un point d'interrogation), "
        "qui demande de deviner lequel de plusieurs centres d'intérêt appartient vraiment à la "
        "personne suivante. Ne révèle jamais lequel. Ne réponds qu'avec la question, rien d'autre, "
        "pas de guillemets."
    ),
    "city": (
        "Tu es un générateur de questions de quiz pour une app de rencontre. Écris EXACTEMENT une "
        "phrase interrogative en français (elle doit se terminer par un point d'interrogation), "
        "qui demande de deviner dans laquelle de plusieurs villes proposées vit vraiment la "
        "personne suivante. Ne révèle jamais laquelle. Ne réponds qu'avec la question, rien "
        "d'autre, pas de guillemets."
    ),
    "bio": (
        "Tu es un générateur de questions de quiz pour une app de rencontre. Écris EXACTEMENT une "
        "phrase interrogative en français (elle doit se terminer par un point d'interrogation), "
        "qui demande de deviner laquelle de plusieurs courtes présentations (bios) appartient "
        "vraiment à la personne suivante. Ne révèle jamais laquelle. Ne réponds qu'avec la "
        "question, rien d'autre, pas de guillemets."
    ),
}
_MAX_PROMPT_LENGTH = 200


def generate_personalized_prompt(display_name: str, bio: str | None, category: str) -> str | None:
    """Tente une question personnalisée via Ollama ; renvoie None sur tout échec ou sortie
    invalide (settings.ollama_enabled=False, conteneur injoignable, timeout, réponse vide,
    trop longue, ou qui ne ressemble pas à une question) — l'appelant retombe alors sur le
    gabarit statique. Ne lève jamais : ce endpoint ne doit jamais échouer parce qu'Ollama est
    indisponible ou lent.

    `bio` n'est envoyée comme contexte que si `category != "bio"` : quand la bio EST le domaine de
    la question (deviner laquelle de plusieurs bios est la vraie), la donner au modèle risquerait
    de la laisser transparaître dans la formulation elle-même — pour les autres catégories, elle ne
    sert qu'à personnaliser le ton, jamais à révéler la bonne réponse (déjà vrai avant : voir
    l'absence de l'intérêt/la ville corrects dans ce contexte)."""
    settings = get_settings()
    if not settings.ollama_enabled:
        return None

    context = f"Prénom : {display_name}."
    if bio and category != "bio":
        context += f" Bio : {bio[:300]}"

    try:
        response = _client.post(
            f"{settings.ollama_base_url}/api/generate",
            json={
                "model": settings.ollama_model,
                # Amorcer la réponse par "Question :" (plutôt que de compter sur les seules
                # instructions) fait sauter le taux de sorties réellement interrogatives d'un
                # modèle 1B d'environ 1/3 à ~2/3 sur des essais manuels — la validation
                # ci-dessous (présence d'un "?") reste le filet de sécurité, pas le seul levier.
                "prompt": f"{_INSTRUCTIONS[category]}\n\n{context}\n\nQuestion :",
                "stream": False,
                # Garde le modèle chargé en mémoire entre deux questions du jour plutôt que de
                # payer un rechargement à froid (l'inactivité par défaut d'Ollama le décharge
                # après quelques minutes) — sur un MVP à faible volume, une génération toutes
                # les quelques minutes suffit à retomber sous ce seuil sans ce réglage.
                "keep_alive": "10m",
                "options": {"temperature": 0.8, "num_predict": 60},
            },
            timeout=settings.ollama_timeout_seconds,
        )
        response.raise_for_status()
        text = response.json().get("response", "").strip().strip('"')
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("Génération Ollama de la question du jour échouée, repli : %s", exc)
        return None

    if not text or len(text) > _MAX_PROMPT_LENGTH or "?" not in text:
        return None
    return text
