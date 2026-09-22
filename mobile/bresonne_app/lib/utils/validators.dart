// Validateurs de champs de formulaire partagés — un seul endroit pour la règle plutôt qu'une
// regex ou un message d'erreur recopié à chaque écran.

// Le backend (`services/otp.py`) ne valide ni ne normalise le numéro : il compare la chaîne
// telle quelle à chaque requête, sans jamais la reformater. Cette regex n'attrape donc qu'une
// saisie clairement invalide côté client (lettres, numéro trop court...) — elle n'impose pas un
// format que le backend n'exige pas lui-même, pour ne jamais bloquer un numéro qui marcherait.
final _phoneDigitsPattern = RegExp(r'^\+?[0-9]{8,15}$');

/// `null` si `value` ressemble à un numéro de téléphone valide, sinon un message d'erreur en
/// français prêt à afficher.
String? validatePhoneNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Le numéro de téléphone est obligatoire.';
  final digitsOnly = trimmed.replaceAll(RegExp(r'[\s.\-()]'), '');
  if (!_phoneDigitsPattern.hasMatch(digitsOnly)) {
    return 'Entrez un numéro de téléphone valide, ex. +33 6 12 34 56 78.';
  }
  return null;
}

final _otpCodePattern = RegExp(r'^[0-9]{6}$');

/// Le code OTP fait toujours 6 chiffres (`core/security.generate_otp_code`) — un format qu'on
/// peut vérifier avant même d'appeler l'API, plutôt que de laisser un backend 400 faire le travail.
String? validateOtpCode(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Entrez le code reçu par SMS.';
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
