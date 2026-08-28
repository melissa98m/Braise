class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      matchId: json['match_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String matchId;
  final String senderId;
  final String body;
  final DateTime createdAt;
}

class DailyQuestion {
  const DailyQuestion({required this.options, required this.answered, required this.isCorrect});

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      options: (json['options'] as List).cast<String>(),
      answered: json['answered'] as bool,
      isCorrect: json['is_correct'] as bool?,
    );
  }

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
