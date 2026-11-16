import {PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage} from 'pdf-lib';
import QRCode from 'qrcode';

export type ConsentDoc = {
  code: string;
  kind: string;
  version: number;
  title: string;
  body: string;
  choices: Record<string, boolean | string>;
  signerName: string;
  subjectName: string;
  church: string;
  device: string;
  acceptedAt: string;
  sha256: string;
  revokedAt: string | null;
  revokedReason: string | null;
  intact: boolean;
};
const choiceLabels: Record<string, string> = {photos: 'Fotos', videos: 'Vídeos', social: 'Redes sociais da igreja', live: 'Transmissões ao vivo'};
const brand = rgb(0.157, 0.361, 0.271),
  dark = rgb(0.086, 0.239, 0.184),
  gold = rgb(0.859, 0.733, 0.439),
  ink = rgb(0.122, 0.165, 0.133),
  muted = rgb(0.373, 0.435, 0.392);

/** Quebra o texto em linhas que cabem na largura (fonte padrão do PDF, alfabeto latino). */
function lines(text: string, font: PDFFont, size: number, width: number) {
  const out: string[] = [];
  for (const para of text.replace(/\r/g, '').split('\n')) {
    let line = '';
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const next = line ? line + ' ' + word : word;
      if (font.widthOfTextAtSize(next, size) > width && line) {
        out.push(line);
        line = word;
      } else line = next;
    }
    out.push(line);
  }
  return out;
}
const safe = (s: string) => s.replace(/[^\n\u0020-\u00ff\u2022\u2014\u2013\u201c\u201d\u2018\u2019\u2026]/g, '');
const when = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

/** PDF do termo assinado: texto exato da versão, escolhas, assinatura eletrônica, código, SHA-256 e QR de verificação. */
export async function consentPdf(d: ConsentDoc, verifyBase = 'https://app.vinhaigrejas.com.br/verificar/') {
  const pdf = await PDFDocument.create();
  pdf.setTitle(d.title + ' · ' + d.code);
  pdf.setAuthor(d.church);
  pdf.setCreator('Vinha');
  pdf.setSubject('Termo de consentimento assinado eletronicamente');
  const regular = await pdf.embedFont(StandardFonts.Helvetica),
    bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const qr = await pdf.embedPng(await QRCode.toDataURL(verifyBase + d.code, {margin: 1, width: 240, color: {dark: '#163d2f', light: '#ffffff'}}));
  const W = 595,
    H = 842,
    M = 48;
  let page: PDFPage = pdf.addPage([W, H]),
    y = H;
  const header = () => {
    page.drawRectangle({x: 0, y: H - 92, width: W, height: 92, color: dark});
    page.drawRectangle({x: 0, y: H - 96, width: W, height: 4, color: gold});
    page.drawRectangle({x: M, y: H - 72, width: 44, height: 44, color: brand});
    page.drawText('V', {x: M + 13, y: H - 62, size: 26, font: bold, color: gold});
    page.drawText(safe(d.church), {x: M + 58, y: H - 50, size: 15, font: bold, color: rgb(1, 1, 1)});
    page.drawText('TERMO ASSINADO ELETRONICAMENTE · ' + d.code, {x: M + 58, y: H - 68, size: 9, font: bold, color: gold});
    y = H - 126;
  };
  const ensure = (need: number) => {
    if (y - need < 150) {
      page = pdf.addPage([W, H]);
      header();
    }
  };
  const write = (text: string, size = 11, font = regular, color = ink, gap = 4) => {
    for (const l of lines(safe(text), font, size, W - 2 * M)) {
      ensure(size + gap);
      page.drawText(l, {x: M, y, size, font, color});
      y -= size + gap;
    }
  };
  header();
  write(d.title, 17, bold, dark, 6);
  y -= 4;
  write(`Versão ${d.version || 'padrão'} · Pessoa: ${d.subjectName}`, 10, regular, muted);
  y -= 10;
  write(d.body, 11, regular, ink, 5);
  y -= 8;
  const marks = Object.entries(d.choices || {}).filter(([, v]) => typeof v === 'boolean');
  if (marks.length) {
    write('Autorizações marcadas', 12, bold, dark, 6);
    for (const [k, v] of marks) write(`${v ? '[X] Autorizo' : '[  ] Não autorizo'} · ${choiceLabels[k] || k}`, 11);
    y -= 8;
  }
  ensure(200);
  page.drawRectangle({x: M, y: y - 166, width: W - 2 * M, height: 166, color: rgb(0.898, 0.933, 0.91)});
  const box = y - 18;
  page.drawText('ASSINATURA ELETRÔNICA', {x: M + 14, y: box, size: 9, font: bold, color: rgb(0.498, 0.392, 0.125)});
  const info = [
    ['Assinado por', d.signerName + (typeof d.choices?.signerCpf === 'string' ? ' · CPF ' + d.choices.signerCpf : '')],
    ['Data e hora (Brasília)', when(d.acceptedAt)],
    ['Aparelho', d.device || 'Aplicativo da igreja'],
    ['Código de verificação', d.code],
    ['Situação', d.revokedAt ? `${d.revokedReason || 'Revogado'} em ${when(d.revokedAt)}` : 'Válido'],
  ];
  info.forEach(([k, v], i) => {
    page.drawText(safe(k) + ':', {x: M + 14, y: box - 18 - i * 16, size: 9.5, font: bold, color: ink});
    page.drawText(safe(v), {x: M + 140, y: box - 18 - i * 16, size: 9.5, font: regular, color: ink});
  });
  page.drawText('Impressão digital SHA-256:', {x: M + 14, y: box - 108, size: 8.5, font: bold, color: muted});
  page.drawText(d.sha256.slice(0, 32), {x: M + 14, y: box - 120, size: 8.5, font: regular, color: muted});
  page.drawText(d.sha256.slice(32), {x: M + 14, y: box - 131, size: 8.5, font: regular, color: muted});
  page.drawImage(qr, {x: W - M - 118, y: y - 140, width: 106, height: 106});
  page.drawText('Confira a autenticidade', {x: W - M - 122, y: y - 146, size: 7.5, font: regular, color: muted});
  y -= 184;
  write(
    `Assinatura eletrônica simples (Lei 14.063/2020, art. 4º, I). Para conferir, aponte a câmera para o QR Code ou acesse ${verifyBase}${d.code}. A impressão digital muda se qualquer palavra do termo for alterada.`,
    8.5,
    regular,
    muted,
    3,
  );
  if (!d.intact) write('ATENÇÃO: o conteúdo armazenado não confere com a impressão digital original.', 10, bold, rgb(0.706, 0.137, 0.094));
  return pdf.save();
}
