import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('nenhuma tela cita o serviço de CEP', () => {
  for (const f of ['app/DashboardApp.tsx', 'app/RegistrationFields.tsx', 'app/useRegistrationFormatting.ts']) {
    assert.doesNotMatch(readFileSync(new URL('../' + f, import.meta.url), 'utf8'), /ViaCEP/i, f);
  }
});
