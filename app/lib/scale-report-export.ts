import ExcelJS from 'exceljs';
import {PDFDocument, StandardFonts, rgb} from 'pdf-lib';
import {scaleMetrics, scaleReportBasis, type ScaleReport} from '../../shared/scale-insights.ts';

export async function scaleWorkbook(report: ScaleReport, period: string) {
  const book = new ExcelJS.Workbook();
  const summary = book.addWorksheet('Resumo');
  summary.addRows([['Igreja', report.unitName], ['Período', period], ['Fuso', report.timezone], ...scaleMetrics(report), ['Critérios', scaleReportBasis]]);
  summary.getColumn(1).width = 31;
  summary.getColumn(2).width = 80;
  summary.getColumn(2).alignment = {wrapText: true, vertical: 'top'};

  const teams = book.addWorksheet('Equipes e funções');
  teams.addRow(['Equipe', 'Função', 'Vagas', 'Preenchidas', 'Convites', 'Confirmações', 'Recusas', 'Pendentes']);
  teams.addRows(report.teamRoles.map((r) => [r.team, r.role, r.required, r.filled, r.invites, r.confirmed, r.declined, r.pending]));
  teams.columns.forEach((column, i) => {
    column.width = i < 2 ? 28 : 16;
  });
  const people = book.addWorksheet('Distribuição');
  people.addRow([`${report.distributionTotal} pessoas no período`]);
  people.addRow(['Pessoa', 'Serviços', 'Atribuições', 'Confirmações']);
  people.addRows(report.distribution.map((r) => [r.name, r.services, r.assignments, r.confirmed]));
  people.columns.forEach((column, i) => {
    column.width = i === 0 ? 45 : 17;
  });
  for (const sheet of book.worksheets) sheet.getRow(1).font = {bold: true, color: {argb: 'FF24563F'}};
  return new Uint8Array(await book.xlsx.writeBuffer());
}

export async function scaleReportPdf(report: ScaleReport, period: string) {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  let page = doc.addPage([595, 842]);
  let y = 800;
  const line = (input: string, size = 11, strong = false) => {
    const face = strong ? bold : font;
    const safe = input.replace(/[^\x20-\x7e\xa0-\xff]/g, '-');
    let current = '';
    const print = (value: string) => {
      if (y < 45) {
        page = doc.addPage([595, 842]);
        y = 800;
      }
      page.drawText(value, {x: 38, y, size, font: face, color: rgb(0.1, 0.24, 0.19)});
      y -= size + 6;
    };
    for (const char of safe) {
      if (face.widthOfTextAtSize(current + char, size) > 515) {
        print(current.trimEnd());
        current = '';
      }
      current += char;
    }
    print(current);
  };
  line('Vinha | Relatório de escalas', 20, true);
  line(report.unitName, 13, true);
  line(`${period} · ${report.timezone}`);
  y -= 12;
  for (const [label, value] of scaleMetrics(report)) line(`${label}  ${value}`);
  line(scaleReportBasis, 9);
  y -= 12;
  line('Equipes e funções', 14, true);
  for (const r of report.teamRoles) {
    line(`${r.team} / ${r.role}`, 11, true);
    line(`${r.filled}/${r.required} vagas · ${r.confirmed}/${r.invites} confirmações · ${r.declined} recusas · ${r.pending} pendências`, 10);
  }
  y -= 12;
  line(`Distribuição por pessoa`, 14, true);
  for (const r of report.distribution) line(`${r.name} · ${r.services} serviço(s) · ${r.assignments} atribuição(ões) · ${r.confirmed} confirmação(ões)`);
  return new Uint8Array(await doc.save());
}
