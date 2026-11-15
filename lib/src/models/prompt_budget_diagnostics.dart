// Diagnostics shared by domain admission and standalone assembly.

enum RetainDecision {
  retain,
  dropOverSubBudget,
  dropOverBudget,
  dropMandatoryOverflow,
}

enum CroppingStage { preBudgetAdmission, finalRetainDrop }

class CroppingTrace {
  const CroppingTrace({
    required this.unitId,
    required this.stage,
    required this.decision,
    required this.reason,
  });

  final String unitId;
  final CroppingStage stage;
  final RetainDecision decision;
  final String reason;
}

class PromptBudgetOverflowException implements Exception {
  PromptBudgetOverflowException({
    required this.code,
    required List<CroppingTrace> trace,
  }) : trace = List<CroppingTrace>.unmodifiable(trace);

  final String code;
  final List<CroppingTrace> trace;

  @override
  String toString() => 'PromptBudgetOverflowException($code)';
}
