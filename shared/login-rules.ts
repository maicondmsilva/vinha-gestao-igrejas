/** Regras da senha mostradas enquanto o membro cria a conta (o Supabase exige ao menos 8 caracteres). */
export function passwordHint(password: string, confirm: string) {
  const items: [boolean, string][] = [
    [password.length >= 8, 'Pelo menos 8 caracteres'],
    [/[A-Za-z]/.test(password) && /\d/.test(password), 'Letras e números'],
    [password.length > 0 && password === confirm, 'As duas senhas são iguais'],
  ];
  return {ok: items.every(([ok]) => ok), items};
}

/** Etapas do cadastro para a igreja: agrupa os campos e diz o que falta em cada uma. */
export const registrationSteps = [
  {key: 'about', title: 'Sobre você', fields: ['full_name', 'birth_date', 'gender', 'marital_status']},
  {key: 'contact', title: 'Contato e documento', fields: ['phone', 'cpf']},
  {key: 'address', title: 'Onde você mora', fields: ['postal_code', 'street', 'number', 'complement', 'district', 'city', 'state']},
] as const;

export function stepMissing(form: Record<string, string>, fields: readonly string[]) {
  return fields.filter((k) => k !== 'complement' && !(form[k] || '').trim());
}
