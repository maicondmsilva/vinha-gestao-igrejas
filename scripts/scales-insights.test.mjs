import test from 'node:test';
import assert from 'node:assert/strict';
import {PDFDocument} from 'pdf-lib';
import ExcelJS from 'exceljs';
import {scaleReportPdf, scaleWorkbook} from '../app/lib/scale-report-export.ts';

test('both export formats preserve the report values and neutralize formula-shaped names', async () => {
  const report = {
    unitName: 'Igreja fictícia',
    timezone: 'America/Sao_Paulo',
    services: 1,
    slots: 2,
    filled: 1,
    invites: 1,
    confirmed: 1,
    declined: 0,
    pending: 0,
    averageReplyMinutes: 5,
    attendanceBase: 1,
    present: 1,
    absent: 0,
    changes: {total: 0, pending: 0, approved: 0},
    teamRoles: [{team: 'Recepção', role: 'Acolher', required: 2, filled: 1, invites: 1, confirmed: 1, declined: 0, pending: 0}],
    distributionTotal: 1,
    distribution: [{id: 'fake', name: '=1+1', services: 1, assignments: 1, confirmed: 1}],
  };
  const book = new ExcelJS.Workbook();
  await book.xlsx.load(await scaleWorkbook(report, '01/11/2026 a 10/11/2026'));
  assert.equal(book.getWorksheet('Resumo').getCell('B5').value, '1 de 2 · 50%');
  const cell = book.getWorksheet('Distribuição').getCell('A3');
  assert.equal(cell.value, '=1+1');
  assert.equal(cell.type, ExcelJS.ValueType.String);
  const pdf = await PDFDocument.load(await scaleReportPdf(report, '01/11/2026 a 10/11/2026'));
  assert.ok(pdf.getPageCount() > 0);
});
