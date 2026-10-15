import { withLegacyContainment } from '../../../lib/release-availability';
import { NextResponse } from 'next/server';
import { env } from 'cloudflare:workers';
import { sessionFrom } from '../../_auth';

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

function makePdf(title: string, paragraphs: string[], church: string, person: string, documentId: string, pastor='Pastor titular', details:string[] = []) {
  const commands: string[] = ['0.10 0.24 0.18 rg', '0 742 595 100 re f', '1 1 1 rg', '42 768 48 48 re f', '0.10 0.24 0.18 rg', `BT /F1 17 Tf 54 784 Td (${esc(church.split(' ').map(x=>x[0]).join('').slice(0,2).toUpperCase())}) Tj ET`, '1 1 1 rg', `BT /F2 18 Tf 112 793 Td (${esc(church)}) Tj ET`, '0.84 0.72 0.42 rg', '42 730 510 4 re f', '0.12 0.16 0.13 rg'];
  let y = 690; commands.push(`BT /F2 17 Tf 42 ${y} Td (${esc(title)}) Tj ET`); y -= 35;
  for (const paragraph of paragraphs) { for (const line of wrap(paragraph)) { commands.push(`BT /F1 10 Tf 42 ${y} Td (${esc(line)}) Tj ET`); y -= 15; } y -= 10; }
  y -= 12; commands.push(`BT /F2 10 Tf 42 ${y} Td (Titular / responsavel:) Tj ET`, `BT /F1 10 Tf 170 ${y} Td (${esc(person || 'Nao informado')}) Tj ET`); y -= 22;
  for(const detail of details){commands.push(`BT /F1 9 Tf 42 ${y} Td (${esc(detail)}) Tj ET`);y-=15} y-=8;
  commands.push(`BT /F2 10 Tf 42 ${y} Td (Versao:) Tj ET`, `BT /F1 10 Tf 90 ${y} Td (1.0 - 25/08/2026) Tj ET`); y -= 55;
  commands.push('0.45 0.50 0.46 RG', `42 ${y} 230 0 l S`, `322 ${y} 230 0 l S`, `BT /F1 9 Tf 72 ${y-16} Td (Assinatura do titular / responsavel) Tj ET`, `BT /F1 9 Tf 356 ${y-16} Td (${esc(pastor)} - Pastor titular) Tj ET`);
  commands.push('0.45 0.50 0.46 rg', `BT /F1 8 Tf 42 42 Td (Documento ${esc(documentId)} | Gerado pela plataforma Vinha) Tj ET`);
  const stream = commands.join('\n'); const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
  ];
  let pdf = '%PDF-1.4\n'; const offsets = [0]; objects.forEach((object, index) => { offsets.push(pdf.length); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; }); const xref = pdf.length; pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`; for (let i=1;i<offsets.length;i++) pdf += `${String(offsets[i]).padStart(10,'0')} 00000 n \n`; pdf += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(pdf);
}

async function legacyGET(request: Request) {
  const session=await sessionFrom(request);if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});const churchId=session.churchId;
  const url = new URL(request.url); const type = url.searchParams.get('type') || 'privacy'; const fallback = terms[type] || terms.privacy;
  const churchRow=await env.DB.prepare('SELECT name,senior_pastor_name FROM churches WHERE id=?').bind(churchId).first<{name:string;senior_pastor_name:string}>();
  const termRow=await env.DB.prepare('SELECT title,content,version FROM consent_terms WHERE church_id=? AND consent_type=? AND active=1 ORDER BY effective_at DESC LIMIT 1').bind(churchId,type).first<{title:string;content:string;version:string}>();
  const personId=url.searchParams.get('personId'); const childId=url.searchParams.get('childId'); let person=url.searchParams.get('person')||''; const details:string[]=[];
  if(personId){const row=await env.DB.prepare('SELECT full_name,cpf,birth_date,email,phone FROM people WHERE id=? AND church_id=?').bind(personId,churchId).first<Record<string,string>>();if(row){person=row.full_name;details.push(`CPF: ${row.cpf||'nao informado'} | Nascimento: ${row.birth_date||'nao informado'}`,`E-mail: ${row.email||'nao informado'} | Telefone: ${row.phone||'nao informado'}`)}}
  if(childId){const child=await env.DB.prepare('SELECT full_name,birth_date,allergies,medical_notes FROM children WHERE id=? AND church_id=?').bind(childId,churchId).first<Record<string,string>>();const guardians=await env.DB.prepare(`SELECT p.full_name,g.relationship,g.is_primary FROM child_guardians g JOIN people p ON p.id=g.guardian_person_id WHERE g.child_id=? AND g.church_id=? ORDER BY g.is_primary DESC`).bind(childId,churchId).all<Record<string,string|number>>();if(child){details.push(`Crianca: ${child.full_name} | Nascimento: ${child.birth_date}`,`Alergias: ${child.allergies||'nao informadas'}`,`Responsaveis vinculados: ${guardians.results.map(g=>`${g.full_name} (${g.relationship})`).join(', ')}`)}}
  const church=churchRow?.name||url.searchParams.get('church')||'Igreja Central'; const paragraphs=[termRow?.content||fallback.paragraphs[0],...fallback.paragraphs.slice(1)];
  const id = `${type.toUpperCase()}-${Date.now().toString(36).toUpperCase()}`; const pdf = makePdf(termRow?.title||fallback.title,paragraphs,church,person,id,churchRow?.senior_pastor_name||'Pastor titular',details);
  return new NextResponse(pdf, { headers: { 'Content-Type': 'application/pdf', 'Content-Disposition': `attachment; filename="${type}-${clean(person||'modelo').toLowerCase().replace(/\s+/g,'-')}.pdf"`, 'Cache-Control': 'no-store' } });
}

export const GET = withLegacyContainment(legacyGET);
