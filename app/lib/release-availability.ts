/**
 * Operational availability is independent of a purchased module/entitlement.
 * Changing this catalog is a reviewed release decision, not a client setting.
 */
export const releaseCatalog = [
  { id: 'inicio', title: 'Visão geral', status: 'pilot', detail: 'Resumo do núcleo cadastral. Piloto ainda em preparação.' },
  { id: 'pessoas', title: 'Pessoas', status: 'pilot', detail: 'Cadastro básico no Supabase; importações, documentos e jornadas ainda não liberados.' },
  { id: 'igrejas', title: 'Igrejas e unidades', status: 'pilot', detail: 'Estrutura cadastral no Supabase; consolidação e autonomia dependem de validação adicional.' },
  { id: 'configuracoes', title: 'Configurações', status: 'pilot', detail: 'Somente os acessos indicados como disponíveis nesta etapa.' },
  { id: 'familias', title: 'Famílias e termos', status: 'development', detail: 'Vínculos, consentimentos e PDFs aguardam migração e validação de acesso.' },
  { id: 'aplicativo', title: 'Aplicativo do membro', status: 'development', detail: 'Aplicativos personalizados ainda não estão publicados nas lojas.' },
  { id: 'kids', title: 'Área Kids', status: 'development', detail: 'Responsáveis, salas e retirada segura aguardam validação ponta a ponta.' },
  { id: 'usuarios', title: 'Usuários e permissões da igreja', status: 'pilot', detail: 'Equipe e convites no Supabase, sujeitos à governança de papéis; envio por e-mail ainda não homologado.' },
  { id: 'eventos', title: 'Cultos e eventos', status: 'development', detail: 'Inscrições, ingressos e recebimentos ainda não liberados para operação real.' },
  { id: 'celulas', title: 'Células', status: 'ready', detail: 'Escopo interno por unidade: cadastro, redes e hierarquia, participantes, visitantes, indicações, transferências com aceite, estudos em texto/links, encontros com chamada, indicadores por ramo, supervisão explícita e avisos internos. E-mail/WhatsApp, arquivos hospedados e consolidação entre unidades não estão incluídos nesta liberação.' },
  { id: 'escalas', title: 'Escalas', status: 'development', detail: 'Publicação e confirmações aguardam migração.' },
  { id: 'louvor', title: 'Louvor', status: 'development', detail: 'Busca musical, cifras e integrações licenciadas ainda não disponíveis.' },
  { id: 'comunicacao', title: 'Comunicação entre membros', status: 'development', detail: 'Chat e notificações dos membros aguardam migração. O atendimento à Vinha é separado.' },
  { id: 'transmissoes', title: 'Transmissões', status: 'development', detail: 'Agendamento e distribuição ainda não disponíveis para operação real.' },
  { id: 'financeiro', title: 'Financeiro da igreja', status: 'development', detail: 'Lançamentos, conciliação e recebimentos ainda não liberados; a cobrança da assinatura é separada.' },
  { id: 'relatorios', title: 'Relatórios cadastrais', status: 'pilot', detail: 'Primeira entrega: contagens cadastrais por unidade e situação. Financeiro, exportações nominais e consolidação continuam em desenvolvimento.' },
] as const;

export function pilotViewAllowed(id: string) {
  return releaseCatalog.some(item => item.id === id && (item.status === 'pilot' || item.status === 'ready'));
}

export const unavailableMessage = 'Este recurso está em desenvolvimento e não está liberado para operações reais. Consulte a equipe Vinha.';

/**
 * Fail closed: preserve legacy implementation for migration, never execute it.
 * No environment variable, plan change or browser setting may bypass this gate.
 * Remove per endpoint only after migration and isolation/regression tests.
 */
export function withLegacyContainment(_legacyHandler: unknown) {
  return async function containedLegacyEndpoint(_request: Request, _context?: unknown): Promise<Response> {
    return Response.json(
      { error: unavailableMessage, code: 'FEATURE_NOT_RELEASED', retryable: false },
      { status: 503, headers: { 'Cache-Control': 'no-store', 'X-Vinha-Availability': 'development' } },
    );
  };
}
