/// Exercises the trained form model knows about.
enum FormExercise { squat, lunge, jumpingJack }

enum FormVerdict { good, fix, noPerson }

/// What the form coach tells the user right now.
class FormFeedback {
  const FormFeedback({
    required this.label,
    required this.verdict,
    required this.message,
    this.exercise,
  });

  /// Raw model label, e.g. `Squat_Wrong_Back`.
  final String label;
  final FormVerdict verdict;
  final String message;

  /// Null for labels that are not about one exercise (`No_Person`).
  final FormExercise? exercise;
}

/// The exercise a move trains, judged by its name; null if the model has
/// nothing to say about it.
FormExercise? exerciseForMove(String moveName) {
  final name = moveName.toLowerCase();
  if (name.contains('squat')) return FormExercise.squat;
  if (name.contains('lunge')) return FormExercise.lunge;
  if (name.contains('jumping jack')) return FormExercise.jumpingJack;
  return null;
}

const _fixMessages = <String, (FormExercise, String)>{
  'Squat_Wrong_Back': (FormExercise.squat, 'Keep your back straight'),
  'Squat_Wrong_Shallow': (FormExercise.squat, 'Go a little deeper'),
  'Squat_Wrong_Knee': (FormExercise.squat, 'Keep your knees over your toes'),
  'Lunge_Wrong_Knee': (
    FormExercise.lunge,
    'Keep your front knee over your ankle',
  ),
  'Lunge_Wrong_Back': (
    FormExercise.lunge,
    'Keep your chest up and back straight',
  ),
  'Jack_Wrong_LowArm': (FormExercise.jumpingJack, 'Raise your arms higher'),
};

const _goodLabels = <String, FormExercise>{
  'Squat_Correct': FormExercise.squat,
  'Lunge_Correct': FormExercise.lunge,
  'Jack_Correct_Up': FormExercise.jumpingJack,
};

/// Turns a stable model label into feedback; null for labels that need no
/// message (`Idle`, `Jack_Down`, which is the legitimate arms-down half of
/// a jumping jack).
FormFeedback? feedbackForLabel(String label) {
  if (label == 'No_Person') {
    return const FormFeedback(
      label: 'No_Person',
      verdict: FormVerdict.noPerson,
      message: 'Step back so your whole body is in view',
    );
  }
  if (_fixMessages[label] case (final exercise, final message)) {
    return FormFeedback(
      label: label,
      verdict: FormVerdict.fix,
      message: message,
      exercise: exercise,
    );
  }
  if (_goodLabels[label] case final exercise?) {
    return FormFeedback(
      label: label,
      verdict: FormVerdict.good,
      message: 'Good form',
      exercise: exercise,
    );
  }
  return null;
}

/// Whether [feedback] should be shown during a move named [moveName].
bool feedbackAppliesToMove(FormFeedback feedback, String moveName) {
  if (feedback.verdict == FormVerdict.noPerson) return true;
  final exercise = exerciseForMove(moveName);
  return exercise != null && feedback.exercise == exercise;
}
