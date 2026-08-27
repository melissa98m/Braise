import hashlib
import secrets

# Paires issues de docs/DESIGN_TOKENS.md (braise / voile / foi) — jamais de photo,
# seulement matière/dégradé, conformément à la direction artistique du cahier des charges.
_ACCENT_PAIRS = [
    ("#FF8C42", "#8A3B12"),  # braise
    ("#9E8CFF", "#3D2E7A"),  # voile
    ("#57D9B0", "#1E5A49"),  # foi
]


def generate_avatar_seed() -> str:
    return secrets.token_hex(8)


def avatar_spec_from_seed(seed: str) -> dict:
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    pair = _ACCENT_PAIRS[int(digest[:8], 16) % len(_ACCENT_PAIRS)]
    angle = int(digest[8:12], 16) % 360
    return {
        "seed": seed,
        "from_color": pair[0],
        "to_color": pair[1],
        "angle_deg": angle,
    }
