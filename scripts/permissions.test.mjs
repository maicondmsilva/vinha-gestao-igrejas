import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {permissionCommand,userTypeLabel} from '../app/lib/permissions.ts';
const m='ab900000-0000-4000-8000-000000000001',u='ab900000-0000-4000-8000-000000000002';

test('conceder seção valida ações, abrangência e campos',()=>{
 assert.deepEqual(permissionCommand({action:'set',data:{membership:m,permission:'finance.entries',unit:u,includeChildren:false,actions:['view','view','create']}}),{action:'set',data:{membership:m,permission:'finance.entries',unit:u,includeChildren:false,actions:['view','create']}});
 assert.throws(()=>permissionCommand({action:'set',data:{membership:m,permission:'finance.entries',unit:'',includeChildren:true,actions:['fly']}}));
 assert.throws(()=>permissionCommand({action:'set',data:{membership:m,permission:'finance.entries',unit:'',includeChildren:true,actions:[]}}));
 assert.throws(()=>permissionCommand({action:'set',data:{membership:m,permission:'finance.entries',unit:'',includeChildren:true,actions:['view'],role:'owner'}}),'campo extra recusado');
 assert.throws(()=>permissionCommand({action:'set',data:{membership:'x',permission:'finance.entries',unit:'',includeChildren:true,actions:['view']}}));
 assert.throws(()=>permissionCommand({action:'grant_all',data:{membership:m}}));
});

test('modelo, remoção e limpeza aceitam só o necessário',()=>{
 assert.equal(permissionCommand({action:'apply_template',data:{membership:m,template:'tesouraria',unit:''}}).data.template,'tesouraria');
 assert.throws(()=>permissionCommand({action:'apply_template',data:{membership:m,template:'drop table',unit:''}}));
 assert.deepEqual(permissionCommand({action:'remove',data:{membership:m,permission:'cells.reports',unit:u}}).data,{membership:m,permission:'cells.reports',unit:u});
 assert.deepEqual(permissionCommand({action:'clear',data:{membership:m}}).data,{membership:m});
});

test('tipo de usuário exibido a partir do papel e das concessões',()=>{
 assert.equal(userTypeLabel('owner',0,false),'Dono do ministério');
 assert.equal(userTypeLabel('admin',0,true),'Administrador local');
 assert.equal(userTypeLabel('admin',0,false),'Administrador do ministério');
 assert.equal(userTypeLabel('member',0,false),'Usuário do app');
 assert.equal(userTypeLabel('member',3,false),'Membro de equipe');
});

test('Usuários e permissões fica em Configurações, separado do cadastro de membros',()=>{
 const settings=readFileSync(new URL('../app/OrganizationSettings.tsx',import.meta.url),'utf8');
 assert.match(settings,/section==='usuarios'\?<><StaffDirectory\/><TeamAccess\/>/);
 const staff=readFileSync(new URL('../app/StaffDirectory.tsx',import.meta.url),'utf8');
 assert.match(staff,/setPermsFor\(user\)\}>Permissões<\/button>/);
 const comm=readFileSync(new URL('../app/CommunicationWorkspace.tsx',import.meta.url),'utf8');
 assert.doesNotMatch(comm,/equipe/i,'Comunicação não tem mais Equipe');
});
