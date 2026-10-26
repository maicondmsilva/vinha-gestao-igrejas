export type MinistryMedia={id:string;unit_id:string;kind:'video'|'live';title:string;description:string;source:string;poster:string;status?:'draft'|'published'|'archived';live_state:'scheduled'|'live'|'ended';starts_at:string|null;ends_at:string|null;download_allowed:boolean;version:number;connected_accounts?:number};
export type AppOpening={kind:'none'|'image'|'video';url:string;title:string;seconds:number;version:number};
export function mediaHttps(value:unknown){if(typeof value!=='string'||value.length>2000)return null;try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&!u.hash&&/^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname)&&!/(?:^|\.)(?:localhost|local|internal|invalid)$/.test(u.hostname)?u.href:null}catch{return null}}
export function mediaSource(value:unknown):{kind:'direct'|'youtube'|'vimeo';url:string;embed:string;downloadable:boolean}|null{
 const raw=mediaHttps(value);if(!raw)return null;const u=new URL(raw),host=u.hostname.toLowerCase().replace(/^www\./,'');
 if(['youtube.com','m.youtube.com','youtu.be','youtube-nocookie.com'].includes(host)){
  const id=host==='youtu.be'?u.pathname.slice(1):u.pathname.startsWith('/embed/')?u.pathname.split('/')[2]:u.pathname.startsWith('/shorts/')?u.pathname.split('/')[2]:u.searchParams.get('v');
  if(!id||!/^[-_a-zA-Z0-9]{11}$/.test(id))return null;return{kind:'youtube',url:'https://www.youtube.com/watch?v='+id,embed:'https://www.youtube-nocookie.com/embed/'+id+'?playsinline=1&rel=0',downloadable:false};
 }
 if(['vimeo.com','player.vimeo.com'].includes(host)){const id=u.pathname.split('/').filter(Boolean).pop();if(!id||!/^\d{1,14}$/.test(id))return null;return{kind:'vimeo',url:'https://vimeo.com/'+id,embed:'https://player.vimeo.com/video/'+id+'?dnt=1',downloadable:false}}
 if(/\.(mp4|m3u8)$/i.test(u.pathname))return{kind:'direct',url:raw,embed:raw,downloadable:/\.mp4$/i.test(u.pathname)};return null;
}
export function openingValid(value:unknown):AppOpening|null{if(!value||typeof value!=='object')return null;const x=value as AppOpening;if(!['none','image','video'].includes(x.kind)||typeof x.title!=='string'||x.title.length>160||!Number.isInteger(x.seconds)||x.seconds<1||x.seconds>15||!Number.isInteger(x.version)||x.version<0)return null;if(x.kind!=='none'&&!mediaHttps(x.url))return null;if(x.kind==='video'&&!(mediaSource(x.url)?.downloadable))return null;return x}
