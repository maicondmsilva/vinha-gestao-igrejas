import test from 'node:test';import assert from 'node:assert/strict';
import {summaryUnit,peopleSummary} from '../app/lib/people-summary.ts';
const unit='11111111-1111-4111-8111-111111111111';
const body={unitId:unit,generatedAt:'2026-10-19T12:00:00Z',counts:{total:'5',members:'2',visitors:'1',integration:'1',other:'1'},cpf:'must-not-escape'};
test('relatório exige unidade explícita única',()=>{assert.equal(summaryUnit(new Request('https://example.test/?unitId='+unit)),unit);for(const query of ['', '?unitId=bad','?unitId='+unit+'&unitId='+unit])assert.throws(()=>summaryUnit(new Request('https://example.test/'+query)))});
test('relatório remove campos extras e valida soma sem arredondamento',()=>{assert.equal('cpf' in peopleSummary(body),false);assert.throws(()=>peopleSummary({...body,counts:{...body.counts,total:'6'}}));assert.throws(()=>peopleSummary({...body,counts:{...body.counts,total:5}}));assert.equal(peopleSummary({...body,counts:{total:'9007199254740993',members:'9007199254740993',visitors:'0',integration:'0',other:'0'}}).counts.total,'9007199254740993')});
