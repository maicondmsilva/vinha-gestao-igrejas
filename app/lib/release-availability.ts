/**
 * Operational availability is independent of a purchased module/entitlement.
 * Changing this catalog is a reviewed release decision, not a client setting.
 */
export const releaseCatalog = [
  { id: 'inicio', title: 'Visão geral', status: 'validation', detail: 'Resumo do núcleo cadastral em validação por módulo.' },
  { id: 'pessoas', title: 'Pessoas', status: 'validation', detail: 'Cadastro básico no Supabase; importações, documentos e jornadas ainda não liberados.' },
  { id: 'igrejas', title: 'Igrejas e unidades', status: 'validation', detail: 'Estrutura cadastral no Supabase; consolidação e autonomia dependem de validação adicional.' },
  { id: 'configuracoes', title: 'Configurações', status: 'validation', detail: 'Identidade institucional, cadastros independentes das igrejas, usuários e permissões. Alterações cadastrais auditadas; publicação e integrações externas não são consideradas concluídas pela configuração.' },
  { id: 'familias', title: 'Famílias e termos', status: 'development', detail: 'Vínculos, consentimentos e PDFs aguardam migração e validação de acesso.' },
  { id: 'aplicativo', title: 'Aplicativo do membro', status: 'development', detail: 'Aplicativos personalizados ainda não estão publicados nas lojas.' },
  { id: 'kids', title: 'Área Kids', status: 'validation', detail: 'K1: cadastro integrado a Pessoas, revisão de visitantes, responsáveis e autorizações com histórico, informações restritas de cuidado. Entrada, retirada presencial, salas, etiquetas e aplicativo nativo não estão liberados nesta etapa.' },
  { id: 'usuarios', title: 'Usuários e permissões da igreja', status: 'validation', detail: 'Equipe e convites no Supabase, sujeitos à governança de papéis; envio por e-mail ainda não homologado.' },
  { id: 'eventos', title: 'Cultos e eventos', status: 'validation', detail: 'Calendário mensal, consulta semanal/diária, categorias e séries recorrentes por igreja. Inscrições, ingressos e check-in na base canônica, com preço no detalhe do rascunho. Recebimentos exigem conta recebedora ativa e verificada. Reembolsos automáticos e lotes avançados não estão disponíveis.' },
  { id: 'celulas', title: 'Células', status: 'ready', detail: 'Cadastro, redes e hierarquia, participantes, visitantes, indicações, transferências, estudos com arquivos privados, chamada, indicadores por rede e consolidação das unidades autorizadas do mesmo ministério. Avisos internos com rotina própria. E-mail e WhatsApp dependem de consentimento, configuração do canal e homologação de entrega; não são declarados ativos sem essa validação.' },
  { id: 'escalas', title: 'Escalas', status: 'development', detail: 'Publicação e confirmações aguardam migração.' },
  { id: 'louvor', title: 'Louvor', status: 'development', detail: 'Busca musical, cifras e integrações licenciadas ainda não disponíveis.' },
  { id: 'comunicacao', title: 'Comunicação da igreja', status: 'validation', detail: 'Avisos públicos e biblioteca de mídia por igreja local. Conversas privadas e envio externo de e-mail ou WhatsApp continuam indisponíveis.' },
  { id: 'transmissoes', title: 'Transmissões', status: 'validation', detail: 'Agendamento e publicação de lives de canais oficiais via YouTube, Vimeo ou HLS; reprodução no aplicativo. Não inclui produção de vídeo ou servidor de ingestão.' },
  { id: 'financeiro', title: 'Financeiro da igreja', status: 'validation', detail: 'F1/F2 e configuração F3: dashboard por igreja, contas, classificação em categoria e subcategoria, contas a pagar/receber, baixas manuais parciais, taxas, séries e histórico protegido. Conexão de provedores depende de configuração e homologação externa. Cobranças automáticas, conciliação e rotinas avançadas continuam indisponíveis; a assinatura da Vinha é separada.' },
  { id: 'relatorios', title: 'Relatórios cadastrais', status: 'validation', detail: 'Primeira entrega: contagens cadastrais por unidade e situação. Financeiro, exportações nominais e consolidação continuam em desenvolvimento.' },
] as const;

export function pilotViewAllowed(id: string) {
  return releaseCatalog.some(item => item.id === id && (item.status === 'validation' || item.status === 'ready'));
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
