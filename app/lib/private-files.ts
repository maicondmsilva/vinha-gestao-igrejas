export const privateFileLimit=4*1024*1024;
export const uuidPattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function memberFilePath(organization:string,person:string,file:string){
 if(!uuidPattern.test(organization)||!uuidPattern.test(person)||!new RegExp('^'+uuidPattern.source.slice(1,-1)+'\\.(pdf|png|jpg)$','i').test(file))return null;
 return `${organization.toLowerCase()}/${person.toLowerCase()}/${file.toLowerCase()}`;
}
export function detectedFile(bytes:Uint8Array){
 if(bytes.length<8)return null;
 if(bytes[0]===0x89&&bytes[1]===0x50&&bytes[2]===0x4e&&bytes[3]===0x47&&bytes[4]===0x0d&&bytes[5]===0x0a&&bytes[6]===0x1a&&bytes[7]===0x0a)return{extension:'png',mime:'image/png'};
 if(bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)return{extension:'jpg',mime:'image/jpeg'};
 if(String.fromCharCode(...bytes.slice(0,5))==='%PDF-')return{extension:'pdf',mime:'application/pdf'};
 return null;
}
export async function boundedBody(request:Request,limit:number){
 if(Number(request.headers.get('content-length'))>limit)throw new Error('body_too_large');
 const reader=request.body?.getReader();if(!reader)return new Uint8Array();
 const chunks:Uint8Array[]=[];let length=0;
 try{for(;;){const result=await reader.read();if(result.done)break;length+=result.value.length;if(length>limit){await reader.cancel();throw new Error('body_too_large')}chunks.push(result.value)}}finally{reader.releaseLock()}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}return bytes;
}
