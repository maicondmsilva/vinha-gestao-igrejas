// Perfil do membro · quanto do cadastro está preenchido, por seção, para o app mostrar o que falta.
const sections = [
  {key: 'personal', label: 'Dados pessoais', fields: [['full_name', 'Nome completo'], ['birth_date', 'Nascimento'], ['gender', 'Gênero'], ['marital_status', 'Estado civil'], ['cpf', 'CPF']]},
  {key: 'contact', label: 'Contato', fields: [['phone', 'Celular']]},
  {key: 'address', label: 'Endereço', fields: [['postal_code', 'CEP'], ['street', 'Rua'], ['number', 'Número'], ['district', 'Bairro'], ['city', 'Cidade'], ['state', 'UF']]},
] as const;
export type ProfileSection = {key: string; label: string; done: number; total: number; missing: string[]};

export function profileProgress(profile: Record<string, string> | null | undefined): {percent: number; sections: ProfileSection[]} {
  const filled = (k: string) => typeof profile?.[k] === 'string' && profile[k].trim() !== '';
  const list = sections.map((s) => {
    const missing = s.fields.filter(([k]) => !filled(k)).map(([, l]) => l);
    return {key: s.key, label: s.label, done: s.fields.length - missing.length, total: s.fields.length, missing};
  });
  const total = list.reduce((n, s) => n + s.total, 0),
    done = list.reduce((n, s) => n + s.done, 0);
  return {percent: Math.round((done / total) * 100), sections: list};
}
