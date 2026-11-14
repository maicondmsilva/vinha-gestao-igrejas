import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PDFDocument} from 'pdf-lib';
import {consentPdf} from '../app/lib/consent-pdf.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const doc = {
  code: 'VNH-7K2Q-9MXA',
  kind: 'kids_image',
  version: 2,
  title: 'Termo de autorização de uso de imagem da criança',
  body: 'Parágrafo um com acentuação: ação, imagem, criança.\n\nParágrafo dois — com travessão e “aspas”.',
  choices: {photos: true, videos: false, social: true, live: false},
  signerName: 'Ana Lúcia Prado',
  subjectName: 'Davi Prado',
  church: 'MPR Igarapava',
  device: 'Android 14',
  acceptedAt: '2026-11-14T17:00:00Z',
  sha256: 'a'.repeat(64),
  revokedAt: null,
  revokedReason: null,
  intact: true,
};

test('PDF do termo: abre, traz metadados e cabe texto longo em mais páginas', async () => {
  const bytes = await consentPdf(doc),
    pdf = await PDFDocument.load(bytes);
  assert.equal(pdf.getTitle(), 'Termo de autorização de uso de imagem da criança · VNH-7K2Q-9MXA');
  assert.equal(pdf.getAuthor(), 'MPR Igarapava');
  assert.equal(pdf.getPageCount(), 1);
  const long = await PDFDocument.load(await consentPdf({...doc, body: 'Linha longa do termo de consentimento. '.repeat(400)}));
  assert.ok(long.getPageCount() > 1, 'texto grande continua em outra página');
});
test('telas e rotas dos termos', () => {
  const app = read('android-app/src/ConsentScreens.tsx'),
    route = read('app/api/consent/pdf/route.ts'),
    verify = read('app/verificar/[code]/page.tsx'),
    sql = read('supabase/migrations/20261114210000_termos_consentimento.sql');
  for (const t of ['Li e concordo', 'Assinar eletronicamente', 'Redes sociais da igreja', 'Transmissões ao vivo']) assert.ok(app.includes(t), t);
  assert.match(route, /p_token: token/, 'link de uso único pelo servidor');
  assert.match(verify, /consent_verify/);
  assert.match(sql, /extensions\.digest\(private\.consent_canonical/, 'impressão digital SHA-256 do texto assinado');
  assert.match(sql, /grant execute on function public\.consent_verify\(text\) to anon,authenticated/);
  assert.match(read('android-app/src/FamilyScreens.tsx'), /kinds=\{\['kids_guardian','kids_image'\]\}/, 'Kids: termos por criança');
  assert.match(read('android-app/src/MemberExperience.tsx'), /kinds=\{\['adult_data','adult_image'\]\}/, 'adulto: termos em Meu perfil');
});
