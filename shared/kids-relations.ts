// Kids · grau do responsável em relação à criança (o que ELE é da criança).
// Parentesco liga a criança à família do responsável; "outro" (amigo, vizinho…) só autoriza buscar.
export const guardianRelations = [
  ['pai_mae', 'Pai ou mãe'],
  ['avo', 'Avô ou avó'],
  ['tio', 'Tio ou tia'],
  ['irmao', 'Irmão ou irmã'],
  ['padrasto_madrasta', 'Padrasto ou madrasta'],
  ['responsavel_legal', 'Responsável legal'],
  ['outro', 'Outro (não é parente)'],
] as const;
export type GuardianRelation = (typeof guardianRelations)[number][0];
export const isKinship = (r: string) => r !== 'outro' && guardianRelations.some(([k]) => k === r);
