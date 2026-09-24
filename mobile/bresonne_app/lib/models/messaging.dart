class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.delivered,
    this.deliveredAt,
    required this.read,
    this.readAt,
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
      delivered: json['delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      read: json['read'] as bool? ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
    );
  }

  ChatMessage copyWith({bool? delivered, DateTime? deliveredAt, bool? read, DateTime? readAt}) {
    return ChatMessage(
      id: id,
      matchId: matchId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      delivered: delivered ?? this.delivered,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      read: read ?? this.read,
      readAt: readAt ?? this.readAt,
    );
  }

  final String id;
  final String matchId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final bool delivered;
  final DateTime? deliveredAt;
  final bool read;
  final DateTime? readAt;
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
