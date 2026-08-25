import { NextResponse } from 'next/server';

const terms: Record<string, { title: string; paragraphs: string[] }> = {
  privacy: { title: 'Termo de Consentimento para Tratamento de Dados', paragraphs: [
    'Autorizo a igreja identificada neste documento a tratar meus dados pessoais para cadastro, cuidado pastoral, participação em atividades e comunicação institucional.',
    'Os dados serão acessados somente por pessoas autorizadas, pelo período necessário às finalidades informadas e às obrigações legais. Posso solicitar acesso, correção ou revogação deste consentimento.',
  ] },
  image: { title: 'Termo de Autorização de Uso de Imagem e Voz', paragraphs: [
    'Autorizo, de forma livre e informada, o uso de minha imagem e voz em registros de cultos, eventos e comunicações institucionais da igreja, sem finalidade comercial independente.',
    'A autorização pode ser revogada para utilizações futuras por solicitação aos administradores da igreja.',
  ] },
  messages: { title: 'Termo de Consentimento para Comunicações', paragraphs: [
    'Autorizo o envio de mensagens relacionadas à comunidade, eventos, escalas, avisos pastorais e conteúdos da igreja por aplicativo, e-mail, SMS ou mensageria.',
    'Posso alterar minhas preferências ou cancelar o recebimento a qualquer momento.',
  ] },
  minors: { title: 'Termo do Responsável por Criança ou Adolescente', paragraphs: [
    'Declaro ser responsável legal ou pessoa expressamente autorizada e consinto com o cadastro do menor para participação nas atividades da Área Kids.',
    'Autorizo o tratamento dos dados necessários à segurança, incluindo contatos, alergias, informações de saúde essenciais, sala, check-in e checkout. A retirada somente poderá ser realizada por pessoa autorizada.',
  ] },
};

function clean(value: string) { return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\x20-\x7E]/g, ''); }
function esc(value: string) { return clean(value).replace(/([\\()])/g, '\\$1'); }
function wrap(text: string, size = 82) { const words = clean(text).split(/\s+/); const lines: string[] = []; let line = ''; for (const word of words) { if (`${line} ${word}`.trim().length > size) { lines.push(line); line = word; } else line = `${line} ${word}`.trim(); } if (line) lines.push(line); return lines; }

function makePdf(title: string, paragraphs: string[], church: string, person: string, documentId: string) {
  const commands: string[] = ['0.10 0.24 0.18 rg', '0 742 595 100 re f', '1 1 1 rg', '42 768 48 48 re f', '0.10 0.24 0.18 rg', `BT /F1 17 Tf 54 784 Td (${esc(church.split(' ').map(x=>x[0]).join('').slice(0,2).toUpperCase())}) Tj ET`, '1 1 1 rg', `BT /F2 18 Tf 112 793 Td (${esc(church)}) Tj ET`, '0.84 0.72 0.42 rg', '42 730 510 4 re f', '0.12 0.16 0.13 rg'];
  let y = 690; commands.push(`BT /F2 17 Tf 42 ${y} Td (${esc(title)}) Tj ET`); y -= 35;
  for (const paragraph of paragraphs) { for (const line of wrap(paragraph)) { commands.push(`BT /F1 10 Tf 42 ${y} Td (${esc(line)}) Tj ET`); y -= 15; } y -= 10; }
  y -= 12; commands.push(`BT /F2 10 Tf 42 ${y} Td (Titular / responsavel:) Tj ET`, `BT /F1 10 Tf 170 ${y} Td (${esc(person || 'Nao informado')}) Tj ET`); y -= 28;
  commands.push(`BT /F2 10 Tf 42 ${y} Td (Versao:) Tj ET`, `BT /F1 10 Tf 90 ${y} Td (1.0 - 25/08/2026) Tj ET`); y -= 55;
  commands.push('0.45 0.50 0.46 RG', `42 ${y} 230 0 l S`, `322 ${y} 230 0 l S`, `BT /F1 9 Tf 72 ${y-16} Td (Assinatura do titular / responsavel) Tj ET`, `BT /F1 9 Tf 372 ${y-16} Td (Representante da igreja) Tj ET`);
  commands.push('0.45 0.50 0.46 rg', `BT /F1 8 Tf 42 42 Td (Documento ${esc(documentId)} | Gerado pela plataforma Vinha) Tj ET`);
  const stream = commands.join('\n'); const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
  ];
  let pdf = '%PDF-1.4\n'; const offsets = [0]; objects.forEach((object, index) => { offsets.push(pdf.length); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; }); const xref = pdf.length; pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`; for (let i=1;i<offsets.length;i++) pdf += `${String(offsets[i]).padStart(10,'0')} 00000 n \n`; pdf += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(pdf);
}

export async function GET(request: Request) {
  const url = new URL(request.url); const type = url.searchParams.get('type') || 'privacy'; const term = terms[type] || terms.privacy;
  const church = url.searchParams.get('church') || 'Igreja Central'; const person = url.searchParams.get('person') || '';
  const id = `${type.toUpperCase()}-${Date.now().toString(36).toUpperCase()}`; const pdf = makePdf(term.title, term.paragraphs, church, person, id);
  return new NextResponse(pdf, { headers: { 'Content-Type': 'application/pdf', 'Content-Disposition': `attachment; filename="${type}-${clean(person||'modelo').toLowerCase().replace(/\s+/g,'-')}.pdf"`, 'Cache-Control': 'no-store' } });
}
