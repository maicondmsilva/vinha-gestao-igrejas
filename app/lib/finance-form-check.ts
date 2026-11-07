import {financeMoneyInput} from './finance-f1.ts';

/** What the browser reports about a field, reduced to what the message needs (easy to test without a DOM). */
export type FieldState = {
  tag: string;
  type: string;
  valueMissing: boolean;
  tooShort: boolean;
  tooLong: boolean;
  rangeUnderflow: boolean;
  rangeOverflow: boolean;
  patternMismatch: boolean;
  typeMismatch: boolean;
  badInput: boolean;
  stepMismatch: boolean;
  customError: boolean;
  customMessage: string;
  minLength: number;
  maxLength: number;
  min: string;
  max: string;
  today: string;
};

const day = (iso: string) => (/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : iso);

/** Plain-language message for one invalid field, in the order the person should fix it. */
export function fieldMessage(f: FieldState): string {
  const date = f.type === 'date' || f.type === 'month';
  if (f.valueMissing) return f.tag === 'select' ? 'Escolha uma opção.' : f.type === 'checkbox' ? 'Marque esta opção.' : f.type === 'file' ? 'Selecione um arquivo.' : 'Preencha este campo.';
  if (f.customError && f.customMessage) return f.customMessage;
  if (f.badInput) return date ? 'Informe uma data válida.' : 'Confira o que foi digitado.';
  if (f.tooShort) return `Use pelo menos ${f.minLength} caracteres.`;
  if (f.tooLong) return `Use no máximo ${f.maxLength} caracteres.`;
  if (f.rangeOverflow) return date ? (f.max === f.today ? 'A data não pode ser futura.' : `Informe uma data até ${day(f.max)}.`) : `O máximo é ${f.max}.`;
  if (f.rangeUnderflow) return date ? `Informe uma data a partir de ${day(f.min)}.` : `O mínimo é ${f.min}.`;
  if (f.patternMismatch || f.typeMismatch) return 'Confira o formato deste campo.';
  if (f.stepMismatch) return 'Confira o valor informado.';
  return 'Confira este campo.';
}

/** Text a person reads in the label, without hints such as "(opcional)" or "· R$" and without the options of a select. */
export function fieldLabel(raw: string): string {
  return raw
    .replace(/\s+/g, ' ')
    .replace(/\(opcional\)|· opcional|· R\$|\(\d+\/\d+\)/gi, '')
    .replace(/\s+·\s*$/, '')
    .trim()
    .slice(0, 60);
}

/**
 * Money fields accept what people type ("R$ 1.234,56"); anything else is flagged before the request leaves
 * the browser. An empty value is left to the required check.
 */
export function moneyFieldError(value: string): string {
  if (!value.trim()) return '';
  return financeMoneyInput(value) === null ? 'Informe um valor como 1.234,56.' : '';
}

/** Summary line shown at the top of the form. */
export function problemSummary(labels: readonly string[]): string {
  const unique = [...new Set(labels.filter(Boolean))];
  if (!unique.length) return 'Revise os campos destacados.';
  return unique.length === 1 ? `Falta corrigir 1 campo: ${unique[0]}.` : `Faltam corrigir ${unique.length} campos: ${unique.join(', ')}.`;
}
