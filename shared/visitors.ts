// Visitantes: textos e máscaras usados pela página do QR Code, pelo Vinha Equipe e pelo painel.
export const visitorHeard: [string, string][] = [
  ['friend', 'Convite de um amigo'],
  ['family', 'Família'],
  ['social', 'Redes sociais'],
  ['online', 'Culto online'],
  ['passing', 'Passei em frente'],
  ['event', 'Evento da igreja'],
  ['other', 'Outro'],
];
export const visitorHeardLabel = (k?: string) => visitorHeard.find(([x]) => x === k)?.[1] || '';

/** (11) 98888-7777 enquanto digita. */
export function visitorPhoneMask(v: string) {
  const d = v.replace(/\D/g, '').slice(0, 11);
  if (d.length <= 2) return d ? '(' + d : '';
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}

/** Mensagem clara para cada recusa do banco. */
export function visitorError(message: string) {
  if (/visitor_name/.test(message)) return 'Digite seu nome e sobrenome.';
  if (/visitor_phone/.test(message)) return 'Digite seu WhatsApp com DDD.';
  if (/visitor_email/.test(message)) return 'Confira o e-mail digitado.';
  if (/visitor_consent/.test(message)) return 'Marque a autorização para a igreja guardar seus dados.';
  if (/visitor_rate/.test(message)) return 'Muitos cadastros agora. Aguarde um minuto e tente de novo.';
  if (/visitor_denied/.test(message)) return 'Você não tem permissão para cadastrar visitantes nesta igreja.';
  if (/visitor_unit_denied/.test(message)) return 'Este QR Code não está mais ativo. Peça um novo na recepção.';
  return 'Não foi possível enviar agora. Tente de novo.';
}

/** Link aberto pelo QR Code de cada igreja local. */
export const visitorUrl = (unit: string) => 'https://app.vinhaigrejas.com.br/visitante/' + unit;
