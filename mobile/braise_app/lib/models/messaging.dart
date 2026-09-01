class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      matchId: json['match_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Absent seulement en théorie (toujours envoyé par le backend) — false par défaut plutôt
      // que de planter sur un message reçu avant un redéploiement serveur.
      read: json['read'] as bool? ?? false,
    );
  }

  ChatMessage copyWith({bool? read}) {
    return ChatMessage(
      id: id,
      matchId: matchId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      read: read ?? this.read,
    );
  }

  final String id;
  final String matchId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final bool read;
}

class DailyQuestion {
  const DailyQuestion({
    required this.prompt,
    required this.options,
    required this.answered,
    required this.isCorrect,
  });

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      prompt: json['prompt'] as String,
      options: (json['options'] as List).cast<String>(),
      answered: json['answered'] as bool,
      isCorrect: json['is_correct'] as bool?,
    );
  }

  final String prompt;
  final List<String> options;
  final bool answered;
  final bool? isCorrect;
}

class DailyQuestionResult {
  const DailyQuestionResult({
    required this.correct,
    required this.correctAnswer,
    required this.flameCount,
  });

  factory DailyQuestionResult.fromJson(Map<String, dynamic> json) {
    return DailyQuestionResult(
      correct: json['correct'] as bool,
      correctAnswer: json['correct_answer'] as String,
      flameCount: json['flame_count'] as int,
    );
  }

  final bool correct;
  final String correctAnswer;
  final int flameCount;
}
