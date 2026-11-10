/** Active contracts must not bypass the isolated proportional billing workflow. */
export function requiresProrationReview(current: Record<string, unknown> | null, next: Record<string, unknown>) {
 if (!current || current.status !== 'active') return false;
 const decisions = (value: unknown) => JSON.stringify(Object.entries((value || {}) as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)));
 return current.plan_id !== next.planId || current.payer_unit_id !== next.payerUnitId ||
  Number(current.due_day) !== Number(next.dueDay) || decisions(current.module_decisions) !== decisions(next.modules);
}
