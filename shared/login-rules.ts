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

export type SignupForm = {name: string; phone: string; unit: string; email: string; password: string; confirm: string; terms: boolean};
/** O que falta para criar a conta, em linguagem simples. Lista vazia = pode enviar. */
export function signupProblems(f: SignupForm) {
  const out: string[] = [];
  if (!f.unit) out.push('Escolha a igreja à qual você pertence.');
  if (
    f.name
      .trim()
      .split(/\s+/)
      .filter((w) => w.length > 1).length < 2
  )
    out.push('Digite seu nome e sobrenome.');
  const digits = f.phone.replace(/\D/g, '');
  if (digits.length < 10 || digits.length > 13) out.push('Digite o WhatsApp com DDD.');
  if (!/^\S+@\S+\.\S+$/.test(f.email.trim())) out.push('Confira o e-mail.');
  if (f.password.length < 8) out.push('A senha precisa ter pelo menos 8 caracteres.');
  else if (f.password !== f.confirm) out.push('As duas senhas precisam ser iguais.');
  if (!f.terms) out.push('Marque que você aceita os termos de uso e a política de privacidade.');
  return out;
}
export function loginProblems(email: string, password: string) {
  const out: string[] = [];
  if (!/^\S+@\S+\.\S+$/.test(email.trim())) out.push('Confira o e-mail.');
  if (!password) out.push('Digite sua senha.');
  return out;
}
/** Traduz os erros do Supabase Auth para o membro. */
export function authError(message: string, signup: boolean) {
  const m = message.toLowerCase();
  if (m.includes('already registered') || m.includes('already been registered') || m.includes('user already exists'))
    return 'Este e-mail já tem conta. Toque em Entrar e use sua senha (ou "Esqueci minha senha").';
  if (m.includes('email not confirmed')) return 'Falta confirmar o e-mail. Abra a mensagem que enviamos e toque no link; depois entre aqui.';
  if (m.includes('invalid login credentials')) return 'E-mail ou senha não conferem.';
  if (m.includes('rate limit') || m.includes('too many')) return 'Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.';
  if (m.includes('password')) return 'Escolha uma senha mais forte, com pelo menos 8 caracteres.';
  if (m.includes('invalid') && m.includes('email')) return 'Este e-mail não é válido. Confira e tente de novo.';
  if (m.includes('network') || m.includes('fetch')) return 'Sem conexão com a internet. Tente de novo.';
  return signup ? 'Não foi possível criar a conta agora. Tente de novo em instantes.' : 'Não foi possível entrar agora. Tente de novo.';
}
