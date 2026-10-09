// Validateurs de champs de formulaire partagés — un seul endroit pour la règle plutôt qu'une
// regex ou un message d'erreur recopié à chaque écran.

// Volontairement permissif : le backend (`schemas/auth.py`, `EmailStr`) reste la seule vraie
// validation. Ici on n'attrape qu'une saisie clairement invalide (pas d'arobase, pas de point dans
// le domaine, espace au milieu) avant l'appel réseau — jamais une règle plus stricte que celle du
// backend, pour ne pas bloquer une adresse qui marcherait.
final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// `null` si `value` ressemble à une adresse email valide, sinon un message d'erreur en français
/// prêt à afficher.
String? validateEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return "L'adresse email est obligatoire.";
  if (!_emailPattern.hasMatch(trimmed)) {
    return 'Entrez une adresse email valide, ex. prenom@exemple.fr.';
  }
  return null;
}

final _otpCodePattern = RegExp(r'^[0-9]{6}$');

/// Le code OTP fait toujours 6 chiffres (`core/security.generate_otp_code`) — un format qu'on
/// peut vérifier avant même d'appeler l'API, plutôt que de laisser un backend 400 faire le travail.
String? validateOtpCode(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Entrez le code reçu par email.';
  if (!_otpCodePattern.hasMatch(trimmed)) {
    return 'Le code contient 6 chiffres.';
  }
  return null;
}

// Miroir de `PublicProfileIn.display_name` (`backend/app/schemas/profile.py`,
// `Field(min_length=1, max_length=40)`) — la même règle, vérifiée avant l'appel réseau.
const displayNameMaxLength = 40;

String? validateDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Le prénom / pseudo est obligatoire.';
  if (trimmed.length > displayNameMaxLength) {
    return 'Le prénom / pseudo ne peut pas dépasser $displayNameMaxLength caractères.';
  }
  return null;
}

// Miroir de `MAX_MESSAGE_LENGTH` (`backend/app/services/messaging.py`) — sans ce plafond côté
// client, un message trop long était silencieusement tronqué par le backend, sans jamais
// prévenir la personne qui l'a tapé.
const messageMaxLength = 2000;
