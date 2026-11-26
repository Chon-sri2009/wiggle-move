/// Body weight assumed for the estimate; the profile has no weight field.
const assumedBodyWeightKg = 70.0;

/// Rough energy use of a play: MET x 3.5 ml/kg/min x weight, at 5 kcal per
/// litre of oxygen (the standard MET formula). An estimate only; the UI says
/// so. [met] is the routine's intensity (resting = 1, brisk cardio ~ 8).
int estimateCalories({required double met, required int durationMs}) {
  if (met <= 0 || durationMs <= 0) return 0;
  final minutes = durationMs / 60000;
  return (met * 3.5 * assumedBodyWeightKg / 200 * minutes).round();
}
