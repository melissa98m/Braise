# Bresonne — Design tokens (dark & light)

Source : *Braise - Tokens dark + light.dc.html* et *Braise - Direction UI.dc.html* fournis par
Melissa. Référence unique pour le futur thème Flutter (Phase 6) — un seul nom de token par rôle,
deux valeurs (sombre = défaut, clair = option système).

| Token | Rôle | Sombre (défaut) | Clair |
|---|---|---|---|
| `surface/root` | Fond d'application | `#07090E` | `#FBF8F3` |
| `surface/1` | Cartes, panneaux | `#0F1420` | `#FFFFFF` |
| `surface/2` | Champs, bulles, options | `#1D2434` | `#F1ECE3` |
| `border/hairline` | Bordures 1 px | `#2C3448` | `#DDD5C7` |
| `border/strong` | Contours de champ 1,75 px | `#3A4459` | `#C6BCAA` |
| `ink/primary` | Titres et corps (15:1) | `#F4F1EA` | `#1A1712` |
| `ink/secondary` | Texte secondaire | `#AAB3C8` (8,3:1) | `#6B6255` (5,4:1) |
| `ink/floor` | Gris minimum autorisé | `#7C879E` (4,6:1) | `#6F6759` (4,9:1) |
| `braise/ink` | Accent en texte / bordure | `#FF8C42` (8,0:1) | `#A8460A` (5,6:1) |
| `braise/fill` | Bouton primaire (fond) | `#FF8C42`, texte `#160B03` | `#A8460A`, texte `#FFF6EE` |
| `braise/tint` | Fond d'état sélectionné | `rgba(255,140,66,.14)` | `rgba(168,70,10,.10)` |
| `voile/ink` | Mystère, verrous, focus | `#9E8CFF` (6,8:1) | `#5B45D6` (6,1:1) |
| `foi/ink` | Confiance, succès | `#57D9B0` (10:1) | `#0F7A5E` (5,0:1) |
| `foi/fill` | Bouton de validation | `#57D9B0`, texte `#04231A` | `#0F7A5E`, texte `#EAFFF8` |
| `alerte` | Vigilance, badge premium | `#FFC761` (11:1) | `#8A6300` (5,1:1) |
| `erreur` | Erreur, signalement | `#FF7B7B` (7,6:1) | `#C0392B` (5,1:1) |
| `focus/ring` | Anneau de focus 3 px | `#9E8CFF` + liseré fond 3 px | `#5B45D6` + liseré fond 3 px |

## Invariants (indépendants du thème)

- **Typo** : Bricolage Grotesque 800/700 (display, titres) · Manrope 500/700 (corps, 17 px min.) ·
  IBM Plex Mono 500 (données, +14 % d'interlettrage).
- **Espacement** : base 4, rythme 8, marge latérale 24 px (20 px ≤ 375 px, 28 px ≥ 414 px).
- **Rayons** : 12 px champs · 16 px cartes · 22 px cartes clés · 26 px média · 44 px cadre appareil.
- **Cibles tapables** : 44×44 px minimum, boutons primaires 56 px, options de réponse 52 px.
- **Signes** (jamais la couleur seule) : diamant plein/contour (braise), cercle hachuré (voile),
  barres pleines/vides + valeur chiffrée (confiance), carré à noyau (vérifié).

## Règle de bascule

Le clair n'est jamais une inversion de luminance : les accents sont réassombris pour tenir AA dans
les deux sens. `braise/fill` (fond de bouton) et `braise/ink` (texte/bordure) restent deux tokens
distincts — c'est le piège n°1 d'un thème clair. Réglage utilisateur à 3 états : Auto (système) ·
Sombre · Clair — sombre reste le défaut à l'installation.

Détail complet et 8 écrans de référence dans le cahier des charges, annexe E.
