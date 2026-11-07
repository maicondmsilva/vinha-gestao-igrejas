import test from 'node:test';
import assert from 'node:assert/strict';
import {fieldLabel, fieldMessage, moneyFieldError, problemSummary} from '../app/lib/finance-form-check.ts';

const base = {tag: 'input', type: 'text', valueMissing: false, tooShort: false, tooLong: false, rangeUnderflow: false, rangeOverflow: false, patternMismatch: false, typeMismatch: false, badInput: false, stepMismatch: false, customError: false, customMessage: '', minLength: -1, maxLength: -1, min: '', max: '', today: '2026-11-07'};

test('mensagem por tipo de problema, em português e sem jargão', () => {
  assert.equal(fieldMessage({...base, valueMissing: true}), 'Preencha este campo.');
  assert.equal(fieldMessage({...base, tag: 'select', valueMissing: true}), 'Escolha uma opção.');
  assert.equal(fieldMessage({...base, type: 'file', valueMissing: true}), 'Selecione um arquivo.');
  assert.equal(fieldMessage({...base, tooShort: true, minLength: 2}), 'Use pelo menos 2 caracteres.');
  assert.equal(fieldMessage({...base, type: 'date', rangeOverflow: true, max: '2026-11-07'}), 'A data não pode ser futura.');
  assert.equal(fieldMessage({...base, type: 'date', rangeOverflow: true, max: '2026-12-31'}), 'Informe uma data até 31/12/2026.');
  assert.equal(fieldMessage({...base, type: 'date', rangeUnderflow: true, min: '2026-10-01'}), 'Informe uma data a partir de 01/10/2026.');
  assert.equal(fieldMessage({...base, type: 'number', rangeOverflow: true, max: '60'}), 'O máximo é 60.');
  assert.equal(fieldMessage({...base, customError: true, customMessage: 'Informe um valor como 1.234,56.'}), 'Informe um valor como 1.234,56.');
  assert.equal(fieldMessage({...base, valueMissing: true, customError: true, customMessage: 'x'}), 'Preencha este campo.');
});

test('nome do campo sem dicas, valores e opções', () => {
  assert.equal(fieldLabel('Valor · R$'), 'Valor');
  assert.equal(fieldLabel('  Centro de custo (opcional) '), 'Centro de custo');
  assert.equal(fieldLabel('Mensagem (12/240)'), 'Mensagem');
  assert.equal(fieldLabel('Subcategoria · opcional'), 'Subcategoria');
});

test('valor em reais conferido antes de enviar', () => {
  for (const ok of ['', '1.234,56', 'R$ 10', '0,00', '12.50']) assert.equal(moneyFieldError(ok), '', ok);
  for (const bad of ['1.23,4', 'abc', '1,000.50']) assert.equal(moneyFieldError(bad), 'Informe um valor como 1.234,56.', bad);
});

test('resumo diz quantos campos faltam e quais', () => {
  assert.equal(problemSummary(['Valor']), 'Falta corrigir 1 campo: Valor.');
  assert.equal(problemSummary(['Valor', 'Categoria', 'Valor']), 'Faltam corrigir 2 campos: Valor, Categoria.');
  assert.equal(problemSummary([]), 'Revise os campos destacados.');
});
