// Termos de consentimento: nomes dos quatro padrão e termos criados pela igreja (painel e app).
export type ConsentAudience = 'adult' | 'kids';
export const consentFixedNames: Record<string, string> = {
  adult_data: 'Dados pessoais (adulto)',
  adult_image: 'Uso de imagem e voz (adulto)',
  kids_guardian: 'Responsável pela criança (Kids)',
  kids_image: 'Imagem da criança (Kids)',
};
export const consentAudienceLabel: Record<ConsentAudience, string> = {adult: 'Adultos assinam por si', kids: 'Responsável assina pela criança'};
/** Identificador de um termo novo: custom_ + 10 letras/números. */
export function newConsentKind(random: () => number = Math.random) {
  const a = 'abcdefghijkmnpqrstuvwxyz23456789';
  let s = '';
  for (let i = 0; i < 10; i++) s += a[Math.floor(random() * a.length)];
  return 'custom_' + s;
}
export const isCustomConsent = (kind: string) => /^custom_[a-z0-9]{6,40}$/.test(kind);
