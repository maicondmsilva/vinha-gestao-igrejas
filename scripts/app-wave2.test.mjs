import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {composeCare,parseCare} from '../shared/kids-care.ts';
import {profileProgress} from '../shared/profile-progress.ts';
import {publicationSource,publishingKinds} from '../shared/publishing.ts';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
test('cuidados da criança viram texto padrão e voltam para os campos',()=>{
 const text=composeCare({food:'sem lactose',allergy:' amendoim ',special:'',noPhotos:true,notes:'chora ao chegar'});
 assert.equal(text,'Restrição alimentar: sem lactose\nAlergias: amendoim\nFotos: não autorizadas\nObservações: chora ao chegar');
 assert.deepEqual(parseCare(text),{food:'sem lactose',allergy:'amendoim',special:'',noPhotos:true,notes:'chora ao chegar'});
 assert.equal(parseCare('Texto antigo livre').notes,'Texto antigo livre','texto antigo é preservado em observações');
 assert.ok(composeCare({food:'x'.repeat(3000),allergy:'',special:'',noPhotos:false,notes:''}).length<=2000);
});
test('porcentagem do cadastro por seção',()=>{
 const empty=profileProgress(null);assert.equal(empty.percent,0);assert.equal(empty.sections.length,3);
 const r=profileProgress({full_name:'Ana',birth_date:'1990-01-01',gender:'Feminino',marital_status:'Casada',cpf:'',phone:'(11) 9',postal_code:'01000-000',street:'Rua A',number:'1',district:'Centro',city:'São Paulo',state:'SP'});
 assert.equal(r.percent,92);assert.deepEqual(r.sections[0].missing,['CPF']);assert.equal(r.sections[2].missing.length,0);
});
test('página da igreja na Comunicação e telas no app',()=>{
 assert.ok(publishingKinds.includes('page'));assert.equal(publicationSource('page','',''),'');
 assert.match(read('shared/dashboard-menu.ts'),/\['paginas','Páginas da igreja'\]/);
 assert.match(read('app/lib/publishing-command.ts'),/d\.kind==='page'\?12000:4000/);
 const exp=read('android-app/src/MemberExperience.tsx');for(const t of ["detail==='files'","detail==='pages'","detail==='relatives'",'<ProfileProgress'])assert.ok(exp.includes(t),t);
 assert.match(read('android-app/src/ChurchInfoScreens.tsx'),/member_church_pages/);
 assert.match(read('android-app/src/MemberRelatives.tsx'),/member_relatives/);
 assert.match(read('android-app/src/FamilyScreens.tsx'),/<KidsCareFields/);
});
