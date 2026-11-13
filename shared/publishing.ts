import {mediaHttps,mediaSource} from './ministry-media.ts';
export const publishingKinds=['notice','video','live','channel','category','banner','file','page'] as const;
export type PublishingKind=typeof publishingKinds[number];
export type Publication={id:string;kind:PublishingKind;title:string;body:string;source:string;poster:string;category_id:string|null;channel_id:string|null;targets:string[];group_id:string|null;group_version:number|null;scope:string;provider:string;starts_at:string|null;ends_at:string|null;download_allowed:boolean;share_allowed:boolean;status:'draft'|'published'|'archived';live_state:'scheduled'|'live'|'ended';version:number;can_manage:boolean;updated_at:string};
export type PublicationGroup={id:string;title:string;targets:string[];active:boolean;version:number};
export type PublisherUnit={id:string;name:string;communication:boolean;broadcasts:boolean};
export type PublisherPage={items:Publication[];total:number;units:PublisherUnit[];groups:PublicationGroup[];categories:Publication[];channels:Publication[]};
export const publicationLabels:Record<PublishingKind,string>={notice:'Avisos e notícias',video:'Vídeos e pregações',live:'Transmissões',channel:'Canais',category:'Categorias',banner:'Banners e atalhos',file:'Arquivos e downloads',page:'Páginas da igreja'};
export function channelSource(value:string,provider:string){if(provider==='youtube'){
 const id=/^UC[-_a-zA-Z0-9]{22}$/.test(value.trim())?value.trim():null;
 if(id)return 'https://www.youtube.com/channel/'+id;
 const url=mediaHttps(value);if(!url)return null;const u=new URL(url);return ['youtube.com','www.youtube.com'].includes(u.hostname)&&/^\/(channel\/UC[-_a-zA-Z0-9]{22}|@[a-zA-Z0-9._-]{3,80})\/?$/.test(u.pathname)?url:null;
 }const s=mediaSource(value);return provider==='hls'&&s?.kind==='direct'&&new URL(s.url).pathname.endsWith('.m3u8')?s.url:provider==='vimeo'&&s?.kind==='vimeo'?s.url:null}
export function publicationSource(kind:PublishingKind,value:string,provider:string){return kind==='category'?value===''?'':null:kind==='channel'?channelSource(value,provider):kind==='video'||kind==='live'?mediaSource(value)?.url||null:value===''&&(kind==='notice'||kind==='page')?'':mediaHttps(value)}
