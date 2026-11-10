import booksData from './bible/catalog.ts';
import provenance from './bible/provenance.ts';
export const bibleBooks=booksData as {id:string;name:string;verses:number[]}[];
export const bibleCredit='Bíblia Livre (BLIVRE), fevereiro de 2018. © Diego Santos, Mario Sérgio e Marco Teles. CC BY 4.0. Fonte: eBible.org.';
export const bibleSource=provenance.sourceInfo,bibleLicense=provenance.licenseUrl;
export type ScriptureRef={book:string;chapter:number;verse?:number};
export type BibleData=Record<string,string[][]>;
export type VerseResult=Required<ScriptureRef>&{text:string};
let cached:Promise<BibleData>|null=null;
export function loadBible(){return cached??(cached=import('./bible/blivre.json').then(m=>m.default as BibleData).catch(e=>{cached=null;throw e}))}
export const fold=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR').trim();
export function validRef(r:ScriptureRef){const b=bibleBooks.find(b=>b.id===r.book);return !!b&&Number.isInteger(r.chapter)&&r.chapter>=1&&r.chapter<=b.verses.length&&(r.verse===undefined||Number.isInteger(r.verse)&&r.verse>=1&&r.verse<=b.verses[r.chapter-1])}
export function referenceLabel(r:ScriptureRef){return (bibleBooks.find(b=>b.id===r.book)?.name||r.book)+' '+r.chapter+(r.verse?':'+r.verse:'')}
export function adjacentChapter(r:ScriptureRef,delta:1|-1):ScriptureRef|null{const i=bibleBooks.findIndex(b=>b.id===r.book),b=bibleBooks[i];if(!b)return null;const ch=r.chapter+delta;if(ch>=1&&ch<=b.verses.length)return {book:b.id,chapter:ch};const next=bibleBooks[i+delta];return next?{book:next.id,chapter:delta===1?1:next.verses.length}:null}
export function searchBible(data:BibleData,query:string,book='',offset=0){const q=fold(query).replace(/\s+/g,' ');if(q.length<3||q.length>100||offset<0)return {items:[] as VerseResult[],more:false};const items:VerseResult[]=[];let matches=0;for(const b of bibleBooks){if(book&&b.id!==book)continue;for(let ch=0;ch<data[b.id].length;ch++)for(let v=0;v<data[b.id][ch].length;v++){const text=data[b.id][ch][v];if(fold(text).replace(/\s+/g,' ').includes(q)){if(matches++<offset)continue;items.push({book:b.id,chapter:ch+1,verse:v+1,text});if(items.length===21)return{items:items.slice(0,20),more:true}}}}return {items,more:false}}
