"""Génère app/services/data/rating_comments_fr.csv, le jeu d'exemples qui entraîne le classifieur
de rancune de services/moderation_ml.py.

Un noyau écrit à la main (CORE_*) est étendu par combinaison de tournures + contextes propres à
Bresonne (déblocage du profil, flammes, question du jour). Trois familles de clauses, pas deux :
- AUTHENTIC_CLAUSES : positif.
- AUTHENTIC_NEGATIVE_CLAUSES : négatif mais légitime (pas de rancune) — indispensable pour que le
  modèle apprenne "déception liée au physique = rancune" plutôt que "ton négatif = rancune" (sans
  ce contraste, une note basse motivée par l'absence de connexion, sans lien avec le physique,
  se faisait flaguer à tort — cf. test_low_score_far_from_unlock_not_flagged_by_rule).
- RANCOR_CLAUSES : dévalorisation physique post-déblocage.

Usage : python3 backend/scripts/generate_rating_dataset.py (pas de dépendance, stdlib only).
Après régénération, relancer `docker compose run --rm backend pytest -k moderation` pour
vérifier qu'aucune régression n'a été introduite (déséquilibre de classes, seuil de décision...).
"""

import csv
from pathlib import Path

OUTPUT_PATH = Path(__file__).parent.parent / "app" / "services" / "data" / "rating_comments_fr.csv"

CORE_AUTHENTIC = [
    "Très à l'écoute, une conversation agréable du début à la fin.",
    "Il a vraiment lu mes réponses avant de poser sa question, j'ai apprécié.",
    "Échange respectueux, on a mis du temps à se dévoiler et c'était bien comme ça.",
    "Ponctuelle dans les réponses, curieuse, une belle rencontre.",
    "Un peu pressé sur la fin mais globalement quelqu'un de respectueux et sincère.",
    "Elle a pris le temps de bien répondre aux questions quotidiennes, agréable.",
    "Bon feeling, humour sympa, j'aimerais continuer à échanger avec lui.",
    "Discussion fluide, elle est restée elle-même du début à la fin.",
    "Poli, à l'écoute, curieux de mes centres d'intérêt.",
    "Rien à redire, une des meilleures conversations que j'ai eues sur l'appli.",
    "Elle a été honnête sur ses attentes dès le départ, j'ai trouvé ça rassurant.",
    "Bonne humeur constante, des questions pertinentes sur mon profil.",
    "Un peu timide au début mais très attentionné une fois la glace brisée.",
    "Conversation sincère, aucune pression pour débloquer le profil trop vite.",
    "Sympathique, drôle, on a de vrais points communs sur la musique.",
    "Elle a respecté mon rythme pour lever le voile, ça m'a mis en confiance.",
    "Curieux et bienveillant, il a posé de bonnes questions sur mes photos de terrain.",
    "Une belle énergie, hâte de voir où ça mène.",
    "Merci pour cette parenthèse, une vraie belle rencontre.",
    "Elle assume totalement qui elle est, ça fait du bien.",
    "Toujours partant pour répondre à la question du jour, ça crée du lien.",
    "On a mis trois semaines à débloquer les photos et ça valait le coup d'attendre.",
    "Pas le coup de foudre visuel mais une connexion réelle, je continue avec plaisir.",
    "Elle m'a mis à l'aise dès le premier message, rare sur ce genre d'appli.",
    "Un peu réservé sur les photos mais adorable en vrai, aucun regret.",
    "Franc du collier sur ses intentions, ça change des habitués du silence radio.",
    "Belle personnalité, les flammes gagnées ensemble avaient un sens.",
    "Content d'avoir pris le temps avant de débloquer, on se connaissait déjà bien.",
    "Elle a une repartie incroyable, les réponses du quiz quotidien étaient hilarantes.",
    "Poli même après avoir vu mon profil complet, ça rassure.",
    "Rien à redire, j'ai passé un bon moment à échanger avec lui.",
    "Elle m'a proposé un vrai rendez-vous plutôt que de rester bloquée dans le chat.",
    "Sincère du début à la fin, aucune mauvaise surprise à l'ouverture du profil.",
    "Curieuse de mes réponses, jamais pressée de voir les photos avant l'heure.",
    "Trois flammes gagnées ensemble et une vraie complicité qui s'est installée.",
    "Elle a pris le temps de connaître ma personnalité avant de demander à débloquer les photos.",
    "Bonne surprise à l'ouverture du profil, exactement l'image que je m'étais faite.",
    "On a fini par se donner rendez-vous en dehors de l'appli, très bon feeling.",
    "Réponses honnêtes au quiz du jour, aucune tentative de deviner la mienne en trichant.",
    "Un profil qui correspond parfaitement à ce qu'il avait raconté, rassurant.",
    "Elle n'a jamais mis la pression pour débloquer plus vite, ça change.",
    "Discussion agréable même après le déblocage, l'alchimie était toujours là.",
    "Gentil et attentionné, hâte de voir si ça continue en dehors de l'appli.",
    "Un vrai coup de cœur, les photos débloquées correspondaient totalement à ce qu'elle avait décrit.",
    "Merci pour cet échange sincère, aucune déception à aucune étape.",
]

CORE_RANCOR = [
    "Franchement pas terrible physiquement, déçu à la découverte.",
    "Je m'attendais à mieux niveau physique, quelle perte de temps.",
    "Les photos ne rendent pas justice, franchement pas mon type au final.",
    "Toute cette attente pour ça, vraiment pas convaincu par le physique.",
    "Pas du tout le genre de physique que j'espérais après tout ce temps.",
    "Déception totale en voyant les vraies photos, ça casse tout.",
    "Physiquement en dessous de ce que je pensais, dommage d'avoir perdu du temps.",
    "Elle n'est vraiment pas jolie sur les photos débloquées, arnaque.",
    "Pas assez bien physiquement pour moi, je regrette d'avoir continué.",
    "Quel gâchis, le visage ne correspond pas du tout à ce que j'imaginais.",
    "Complètement différent en vrai, une vraie tromperie sur la marchandise.",
    "Insupportable, ne mérite aucune confiance, à éviter absolument.",
    "Menteur et manipulateur, ne perdez pas votre temps avec cette personne.",
    "Physique très décevant, je me suis senti trompé après le déblocage.",
    "Pas du tout intéressant une fois qu'on voit à quoi il ressemble vraiment.",
    "Grosse déception visuelle, je n'aurais jamais continué si j'avais su.",
    "Vraiment laide en vrai, tout ça pour ça.",
    "Perte de temps totale, le physique ne va pas du tout avec la personnalité vendue.",
    "Toutes ces flammes gagnées pour ça, quelle déception une fois les photos débloquées.",
    "On a discuté trois semaines pour rien, le déblocage a tout gâché.",
    "Vraiment pas terrible une fois le profil complet révélé, perte de temps.",
    "Les photos débloquées ne ressemblaient à rien de ce qu'on imaginait.",
    "Toute cette attente pour découvrir un visage qui ne me plaît pas du tout.",
    "Je me suis senti trompé quand les vraies photos sont enfin apparues.",
    "Après toutes ces questions du jour, quelle arnaque niveau physique.",
    "Le déblocage a cassé toute l'alchimie, franchement pas mon type.",
    "Autant de flammes accumulées pour un résultat aussi décevant physiquement.",
    "Elle a menti sur son âge et ça se voit clairement sur les vraies photos.",
    "Dommage d'avoir débloqué, j'aurais préféré ne jamais voir son visage.",
    "Perte de temps totale, rien à voir avec les photos qu'il avait mises.",
    "Le suspense ne valait vraiment pas le coup, grosse désillusion visuelle.",
    "Encore une fois trompé par l'appli, le physique ne suit vraiment pas.",
    "Toute cette énergie dépensée en discussion pour un déblocage aussi raté.",
    "Clairement pas le genre à assumer ses vraies photos, mensonge total.",
    "Le profil débloqué ne correspond en rien aux photos de profil initiales, grosse arnaque.",
    "Il a clairement utilisé des photos vieilles de dix ans, quelle tromperie.",
    "Toutes ces questions du jour pour finir déçu au moment du déblocage, dommage.",
    "Rendez-vous annulé sur le champ après avoir vu les vraies photos, minable.",
    "Filtre énorme sur les photos de profil, rien à voir en vrai.",
    "Un physique complètement différent de ce qui était affiché avant le déblocage.",
    "Elle a menti sur son âge et ça se voit clairement une fois débloqué.",
    "Aucune alchimie une fois les photos réelles découvertes, perte de temps totale.",
    "Grosse désillusion à l'ouverture du profil complet, je regrette d'avoir continué.",
    "Encore une fois piégé par des photos retouchées, franchement lassant.",
    "Toute cette énergie pour un profil qui ne ressemble à rien une fois débloqué.",
]

# --- génération combinatoire (sujets invariants -> pas d'accord de genre à gérer) --------------

AUTHENTIC_CLAUSES = [
    "La conversation est restée agréable et respectueuse",
    "L'échange est resté sincère et sans pression",
    "La personnalité correspondait exactement à ce qui avait été annoncé",
    "L'alchimie est restée intacte",
    "Le profil débloqué correspondait parfaitement aux attentes",
    "La bienveillance était au rendez-vous",
    "La curiosité et l'écoute ne se sont jamais démenties",
    "Le naturel et l'honnêteté ont été constants",
    "La patience et le respect du rythme de l'autre étaient évidents",
    "La complicité s'est installée naturellement",
    "L'humour et la légèreté ont rendu chaque échange agréable",
    "La sincérité du profil s'est confirmée à l'ouverture",
    "Le feeling est resté bon d'un bout à l'autre",
    "La discussion a gardé son charme même après le déblocage",
    "L'écoute et le respect n'ont jamais faibli",
]

AUTHENTIC_DETAILS = [
    "dès les premiers messages",
    "tout au long des questions du jour",
    "même après le déblocage du profil complet",
    "malgré l'attente avant de débloquer les photos",
    "au fil des flammes gagnées ensemble",
    "jusqu'au rendez-vous pris en dehors de l'appli",
    "après plusieurs semaines d'échange",
    "dès le déblocage du profil privé",
    "à chaque nouvelle question quotidienne",
    "du tout début jusqu'à la fin de la conversation",
]

# Négatif mais légitime (pas de rancune) : sans ce contraste, le modèle apprend "ton négatif =
# rancune" au lieu de "déception liée au physique/aux photos = rancune", et flague à tort une
# note basse motivée par l'absence de connexion (cf. test_low_score_far_from_unlock_not_flagged_by_rule).
AUTHENTIC_NEGATIVE_CLAUSES = [
    "Le courant n'est pas vraiment passé entre nous",
    "L'alchimie n'était pas au rendez-vous",
    "On n'était pas compatibles sur le fond",
    "Aucune connexion ne s'est créée malgré une discussion agréable",
    "Le feeling n'y était pas de mon côté",
    "Nos personnalités ne collaient pas vraiment",
    "L'alchimie manquait malgré des échanges respectueux",
    "On n'était pas sur la même longueur d'onde",
    "L'alchimie n'a pas fonctionné, sans rancune particulière",
    "Ça ne matchait pas vraiment entre nous sur le fond",
]

AUTHENTIC_NEGATIVE_DETAILS = [
    "mais l'échange est resté respectueux",
    "sans aucune mauvaise expérience à signaler",
    "malgré une conversation sympathique",
    "mais rien à reprocher à son comportement",
    "sans que ça remette en cause sa gentillesse",
    "malgré des points communs sur le papier",
    "mais aucune déception liée au profil ou aux photos",
    "sans rapport avec le physique, juste une question de feeling",
    "malgré une discussion honnête jusqu'au bout",
    "mais un échange resté cordial et sincère",
]

RANCOR_CLAUSES = [
    "Le physique ne correspond absolument pas aux attentes",
    "Les vraies photos sont une vraie déception",
    "Le déblocage du profil a cassé toute l'alchimie",
    "Le visage découvert ne ressemble en rien aux photos de profil",
    "Cette rencontre s'est révélée être une grosse arnaque physique",
    "Le profil débloqué ne tient clairement pas ses promesses",
    "Les photos de profil étaient largement retouchées",
    "L'écart entre les photos et la réalité est énorme",
    "Le charme a disparu dès l'ouverture du profil complet",
    "La déception physique a gâché toute la conversation",
    "Le mensonge sur l'âge saute aux yeux une fois débloqué",
    "Le décalage entre le discours et le physique est flagrant",
    "La déception a été immédiate à la vue des vraies photos",
    "Le résultat ne valait clairement pas l'attente",
    "Cette histoire s'est terminée en grosse désillusion visuelle",
]

RANCOR_DETAILS = [
    "après trois semaines d'attente",
    "après seulement deux jours d'échange",
    "malgré toutes les flammes gagnées",
    "après avoir répondu à plusieurs questions du jour",
    "après un mois de discussion",
    "dès le lendemain du déblocage",
    "après avoir enfin débloqué les photos",
    "juste avant le rendez-vous prévu",
    "après avoir accumulé cinq flammes ensemble",
    "au moment tant attendu du déblocage",
]


def generate(clauses: list[str], details: list[str]) -> list[str]:
    return [f"{clause}, {detail}." for clause in clauses for detail in details]


def main() -> None:
    authentic = list(
        dict.fromkeys(
            CORE_AUTHENTIC
            + generate(AUTHENTIC_CLAUSES, AUTHENTIC_DETAILS)
            + generate(AUTHENTIC_NEGATIVE_CLAUSES, AUTHENTIC_NEGATIVE_DETAILS)
        )
    )
    rancor = list(dict.fromkeys(CORE_RANCOR + generate(RANCOR_CLAUSES, RANCOR_DETAILS)))

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_ALL)
        writer.writerow(["text", "label"])
        for text in authentic:
            writer.writerow([text, "authentic"])
        for text in rancor:
            writer.writerow([text, "rancor"])

    print(f"authentic: {len(authentic)} (dont {len(CORE_AUTHENTIC)} noyau)")
    print(f"rancor: {len(rancor)} (dont {len(CORE_RANCOR)} noyau)")
    print(f"total: {len(authentic) + len(rancor)} -> {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
