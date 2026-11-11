/**
 * Plain-language messages for the reasons the finance database already reports (the exception name in
 * the error message). Only known reasons are translated; anything else keeps each route's generic text,
 * so no internal detail ever reaches the screen. HTTP status codes stay as each route decides.
 */
const reasons: Record<string, string> = {
  period_closed: 'Este mês já foi fechado. Reabra o período em Fechamento mensal para alterar.',
  ledger_period_closed: 'Este mês já foi fechado. Reabra o período em Fechamento mensal para alterar.',
  period_already_closed: 'Este mês já está fechado.',
  ledger_already_closed: 'Este mês já está fechado.',
  invalid_account: 'A conta escolhida está inativa ou não pertence a esta igreja. Escolha outra conta.',
  account_unavailable: 'A conta escolhida está inativa ou não pertence a esta igreja. Escolha outra conta.',
  invalid_category: 'Escolha uma categoria ativa do tipo certo (entrada ou saída).',
  invalid_classification: 'Escolha uma categoria ativa do tipo certo (entrada ou saída).',
  classification_unavailable: 'A categoria ou a conta desta finalidade foi desativada. Revise a finalidade em Recebimentos digitais.',
  invalid_parent: 'A categoria principal escolhida não é válida para esta subcategoria.',
  invalid_center: 'O centro de custo escolhido está inativo. Escolha outro ou deixe em branco.',
  invalid_supplier: 'O fornecedor escolhido está inativo. Escolha outro ou digite só o nome.',
  person_denied: 'Esta pessoa não pode ser vinculada a este lançamento. Digite só o nome.',
  member_access_denied: 'Esta pessoa não pode ser vinculada a este lançamento. Digite só o nome.',
  opening_already_exists: 'Esta conta já tem saldo inicial. Edite o saldo inicial existente.',
  catalog_conflict: 'Já existe um cadastro com este nome.',
  catalog_limit: 'Limite de cadastros atingido. Desative itens que não usa mais.',
  archive_children_first: 'Desative primeiro as subcategorias desta categoria.',
  shared_catalog_denied: 'Este cadastro é compartilhado pela administração e não pode ser alterado aqui.',
  reason_required: 'Informe a observação ou a justificativa.',
  invalid_due_date: 'Confira a data de vencimento.',
  invalid_series: 'Confira a quantidade (de 2 a 60) e o intervalo das parcelas.',
  title_already_settled: 'Esta conta já foi totalmente recebida ou paga.',
  settlement_limit: 'Este título atingiu o limite de baixas. Fale com a Vinha.',
  multiple_fee_categories: 'As taxas deste título usam categorias diferentes. Estorne as baixas antes de editar.',
  use_settlement_reversal_first: 'Estorne a baixa antes de alterar este lançamento.',
  digital_adjustment_required: 'Lançamentos de pagamentos online são ajustados pelo provedor e não podem ser editados aqui.',
  entry_revision_not_allowed: 'Este lançamento não pode ser editado. Use o estorno.',
  undo_reconciliation_first: 'Desfaça a conciliação antes de alterar este lançamento.',
  entry_changed: 'Outra pessoa alterou este lançamento. Atualize para ver a versão atual.',
  entry_conflict: 'Outra pessoa alterou este lançamento. Atualize para ver a versão atual.',
  title_conflict: 'Outra pessoa alterou esta conta. Atualize para ver a versão atual.',
  request_conflict: 'Este pedido já foi enviado com outros dados. Atualize a lista antes de repetir.',
  invalid_revision: 'Outra pessoa alterou este registro. Atualize para ver a versão atual.',
  same_version_conflict: 'Outra pessoa alterou este registro. Atualize para ver a versão atual.',
  entry_not_found: 'Lançamento não encontrado. Atualize a lista.',
  entry_unavailable: 'Lançamento não encontrado. Atualize a lista.',
  title_not_found: 'Conta não encontrada. Atualize a lista.',
  finance_access_denied: 'Você não tem acesso financeiro a esta igreja.',
  finance_scope_denied: 'Você não tem acesso financeiro a todas as igrejas escolhidas.',
  ledger_access_denied: 'Você não tem acesso financeiro a esta igreja.',
  select_one_unit: 'Escolha uma única igreja em Igreja/Filial para fazer esta operação.',
  report_limit_reduce_period: 'Período muito grande para este relatório. Reduza o intervalo de datas.',
  receiver_unavailable: 'A conta recebedora não está ativa. Confira em Contas recebedoras.',
  receiver_not_ready: 'A conta recebedora ainda não está pronta para receber. Confira em Contas recebedoras.',
  entry_already_reversed: 'Este lançamento já foi estornado e não pode ser excluído.',
  entry_from_statement: 'Este lançamento veio do extrato bancário. Desfaça pela Conciliação.',
  finance_permission_denied: 'Você não tem permissão para esta ação no Financeiro. Peça ao administrador em Configurações › Usuários e permissões.',
  purpose_unavailable: 'Esta finalidade de recebimento está desativada.',
};

/** Friendly text for a known database reason, or null to let the route use its own generic message. */
export function financeReason(message?: string | null): string | null {
  const key = (message || '').trim();
  return Object.prototype.hasOwnProperty.call(reasons, key) ? reasons[key] : null;
}
