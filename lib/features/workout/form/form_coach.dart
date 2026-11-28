import 'form_feedback.dart';
import 'form_smoother.dart';

/// Smoothing between the model's per-frame probabilities and the feedback on
/// screen.
class FormCoach {
  FormCoach(this.labels, {FormSmoother? smoother})
    : _smoother = smoother ?? FormSmoother();

  /// Class names, in the order of the probabilities passed to [update].
  final List<String> labels;
  final FormSmoother _smoother;

  /// Feedback for the stable label; null when there is nothing to say.
  FormFeedback? current;

  /// Feeds one frame's probabilities and returns [current] (updated).
  FormFeedback? update(List<double> probabilities) {
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    final stable = _smoother.add(labels[best], probabilities[best]);
    return current = stable == null ? null : feedbackForLabel(stable);
  }
}
