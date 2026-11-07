import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {parseInline, parseRichText, richTextImages, richTextPlain, safeHref} from '../shared/rich-text.ts';
import {imageMime} from '../shared/image-files.ts';

const id = 'c4ca4238-a0b9-2382-0dcc-509a6f75849b';

test('texto do aviso: blocos e marcas', () => {
  const b = parseRichText(
    `## Culto de domingo\nVenha com **toda a família** e *traga um amigo*.\nSegunda linha.\n\n- Louvor\n- Palavra\n\n1. Chegue cedo\n2. Estacione ao lado\n\n> Deus é fiel\n\n![Igreja reunida](img:${id})`,
  );
  assert.deepEqual(
    b.map((x) => x.type),
    ['heading', 'paragraph', 'list', 'list', 'quote', 'image'],
  );
  assert.equal(b[0].level, 2);
  assert.deepEqual(b[1].children[1], {type: 'bold', children: [{type: 'text', text: 'toda a família'}]});
  assert.equal(b[2].ordered, false);
  assert.equal(b[3].ordered, true);
  assert.equal(b[3].items.length, 2);
  assert.deepEqual(b[5], {type: 'image', id, alt: 'Igreja reunida'});
  assert.deepEqual(richTextImages(`![a](img:${id})\n![b](img:nao-e-id)`), [id]);
});

test('segurança: links só https, e-mail e telefone; HTML fica como texto', () => {
  assert.equal(safeHref('javascript:alert(1)'), null);
  assert.equal(safeHref('http://site.com'), null);
  assert.equal(safeHref('https://user@site.com'), null);
  assert.equal(safeHref('https://vinhaigrejas.com.br/eventos/1'), 'https://vinhaigrejas.com.br/eventos/1');
  assert.equal(safeHref('tel:(11) 99999-0000'), 'tel:11999990000');
  assert.deepEqual(parseInline('[clique](javascript:alert(1))'), [{type: 'text', text: '[clique](javascript:alert(1))'}]);
  assert.deepEqual(parseInline('<img src=x onerror=alert(1)>'), [{type: 'text', text: '<img src=x onerror=alert(1)>'}]);
  const web = readFileSync(new URL('../app/RichText.tsx', import.meta.url), 'utf8');
  assert.doesNotMatch(web, /dangerouslySetInnerHTML/);
  assert.match(web, /rel="noopener noreferrer nofollow"/);
});

test('avisos antigos (texto puro) seguem iguais e prévias saem sem marcas', () => {
  const old = 'Culto às 19h.\nTraga sua Bíblia!';
  assert.deepEqual(parseRichText(old), [{type: 'paragraph', children: [{type: 'text', text: old}]}]);
  assert.equal(richTextPlain('## Título\n**Forte** e [link](https://a.com)\n- um\n- dois'), 'Título\n\nForte e link\n\n• um\n• dois');
  assert.equal(richTextPlain('x'.repeat(50), 10), 'xxxxxxxxx…');
});

test('tipo de imagem pelo conteúdo do arquivo', () => {
  assert.equal(imageMime(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0])), 'image/png');
  assert.equal(imageMime(new Uint8Array([0xff, 0xd8, 0xff, 0xe0])), 'image/jpeg');
  assert.equal(imageMime(new TextEncoder().encode('RIFF\0\0\0\0WEBPVP8 ')), 'image/webp');
  assert.equal(imageMime(new TextEncoder().encode('<svg onload=alert(1)>')), null, 'SVG recusado');
  assert.equal(imageMime(new TextEncoder().encode('GIF89a......')), null);
});

function route(path, names, deps) {
  const src = ts
    .transpileModule(readFileSync(new URL(path, import.meta.url), 'utf8'), {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext}})
    .outputText.replace(/^import .*;\r?\n/gm, '')
    .replaceAll('export async function', 'async function');
  return new Function(...names, src + ';return{GET,POST}')(...deps);
}

test('API do banco de imagens: ministério da sessão, arquivo validado antes do banco', async () => {
  const calls = [],
    uploads = [];
  const r = route(
    '../app/api/publishing-images/route.ts',
    ['authorizeSupabaseChurch', 'db', 'supabaseAdminClient', 'boundedBody', 'uuidPattern', 'imageMime'],
    [
      async () => ({access: {membership: {organization_id: 'verified-org'}}}),
      () => ({rpc: async (n, a) => (calls.push([n, a]), {data: a.p_action === 'prepare' ? {ok: true, path: 'p/x'} : {ok: true, items: []}, error: null})}),
      () => ({storage: {from: () => ({upload: async (...x) => (uploads.push(x), {error: null})})}}),
      async (req) => new Uint8Array(await req.arrayBuffer()),
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      imageMime,
    ],
  );
  const unit = '00000000-0000-4000-8000-000000000001';
  assert.equal((await r.GET(new Request('https://vinha.test/api/publishing-images'))).status, 400);
  const svg = await r.POST(new Request(`https://vinha.test/api/publishing-images?unit=${unit}`, {method: 'POST', body: '<svg/>'}));
  assert.equal(svg.status, 400);
  assert.equal(calls.length, 0, 'arquivo inválido nem chega ao banco');
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]);
  const ok = await r.POST(new Request(`https://vinha.test/api/publishing-images?unit=${unit}&name=Capa`, {method: 'POST', body: png}));
  assert.equal(ok.status, 200);
  assert.deepEqual(calls[0][1].p_data, {mime: 'image/png', bytes: 10, name: 'Capa'});
  assert.equal(calls[0][1].p_org, 'verified-org');
  assert.equal(uploads[0][0], 'p/x');
  assert.equal(calls[1][1].p_action, 'finish');
  const bad = await r.POST(
    new Request(`https://vinha.test/api/publishing-images?unit=${unit}`, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({action: 'delete', id: unit}),
    }),
  );
  assert.equal(bad.status, 400);
});

test('telas usam o texto formatado', () => {
  assert.match(readFileSync(new URL('../app/PublishingWorkspace.tsx', import.meta.url), 'utf8'), /kind==='notice'\?<RichTextEditor/);
  assert.match(readFileSync(new URL('../app/MemberChurchChoice.tsx', import.meta.url), 'utf8'), /<RichText body=\{p\.body\}\/>/);
  assert.match(readFileSync(new URL('../android-app/src/MemberExperience.tsx', import.meta.url), 'utf8'), /<RichText body=\{post\.body\}/);
});
