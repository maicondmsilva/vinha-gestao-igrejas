// Louvor: transposição de cifras e leitura de linhas com acordes. Usado no painel, no app web e no Android.
const sharp=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
const flat=['C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'];
const index=(note:string)=>{const i=sharp.indexOf(note);return i>=0?i:flat.indexOf(note)};
/** Tons que se escrevem com bemóis (escolha da grafia ao transpor). */
const flatKeys=new Set(['F','Bb','Eb','Ab','Db','Gb','Dm','Gm','Cm','Fm','Bbm','Ebm']);
/** Semitons entre dois tons (0 a 11). Tom vazio ou inválido = 0. */
export function semitones(from:string,to:string){
 const a=index((from.match(/^[A-G](#|b)?/)||[''])[0]),b=index((to.match(/^[A-G](#|b)?/)||[''])[0]);
 return a<0||b<0?0:(b-a+12)%12;
}
function moveNote(note:string,steps:number,useFlats:boolean){const i=index(note);if(i<0)return note;const n=(i+steps+120)%12;return (useFlats?flat:sharp)[n]}
/** Transpõe um acorde (ex.: "F#m7/C#") mantendo a qualidade e o baixo. */
export function transposeChord(chord:string,steps:number,useFlats=false){
 if(!steps)return chord;
 return chord.replace(/^([A-G](?:#|b)?)([^/]*)(?:\/([A-G](?:#|b)?))?$/,(_m,root:string,rest:string,bass?:string)=>moveNote(root,steps,useFlats)+rest+(bass?'/'+moveNote(bass,steps,useFlats):''));
}
/** Transpõe todos os acordes entre colchetes de uma cifra: "[G]Santo [D/F#]santo". */
export function transposeChart(chart:string,from:string,to:string){
 const steps=semitones(from,to),useFlats=flatKeys.has(to);
 return steps?chart.replace(/\[([^\]\s]{1,12})\]/g,(_m,c:string)=>'['+transposeChord(c,steps,useFlats)+']'):chart;
}
/** Divide uma linha de cifra em pares acorde + texto, para desenhar o acorde acima da letra. */
export function chartLine(line:string){
 const parts:{chord:string;text:string}[]=[];let rest=line;const first=rest.indexOf('[');
 if(first!==0){parts.push({chord:'',text:first<0?rest:rest.slice(0,first)});if(first<0)return parts;rest=rest.slice(first)}
 for(const m of rest.matchAll(/\[([^\]]*)\]([^[]*)/g))parts.push({chord:m[1],text:m[2]});
 return parts;
}
