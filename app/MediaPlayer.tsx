"use client";
import {useEffect,useRef,useState} from 'react';
import {mediaSource,mediaHttps} from '../shared/ministry-media';
type Props={source:string;poster?:string;title:string;onProgress?:(seconds:number)=>void;start?:number};
export default function MediaPlayer({source,poster='',title,onProgress,start=0}:Props){
 const media=mediaSource(source),[play,setPlay]=useState(false);
 if(!media)return <p>Formato não disponível para reprodução. Confira o link com a igreja.</p>;
 if(media.kind==='direct')return <DirectVideo key={media.url} source={media.url} title={title} poster={poster} start={start} onProgress={onProgress}/>;
 return play?<iframe title={title} src={media.embed} allow="fullscreen; picture-in-picture; encrypted-media" referrerPolicy="strict-origin-when-cross-origin" allowFullScreen style={{border:0,width:'100%',aspectRatio:'16/9',borderRadius:12}}/>:<div><p>A reprodução usa {media.kind==='youtube'?'YouTube':'Vimeo'}. O player será carregado ao continuar.</p><button type="button" onClick={()=>setPlay(true)}>Reproduzir {title}</button></div>;
}
function DirectVideo({source,poster='',title,start=0,onProgress}:Props){
 const video=useRef<HTMLVideoElement>(null),[failed,setFailed]=useState(false),[revision,setRevision]=useState(0),last=useRef(0);
 useEffect(()=>{let active=true;let destroy:(()=>void)|undefined;const node=video.current;if(!node)return;setFailed(false);
 if(/\.m3u8(?:\?|$)/i.test(source)&&!node.canPlayType('application/vnd.apple.mpegurl')){
 void import('hls.js').then(({default:Hls})=>{if(!active)return;if(!Hls.isSupported()){setFailed(true);return}const player=new Hls({enableWorker:false});destroy=()=>player.destroy();player.on(Hls.Events.ERROR,(_,data)=>{if(data.fatal)setFailed(true)});player.loadSource(source);player.attachMedia(node)}).catch(()=>{if(active)setFailed(true)})
 }else node.src=source;
 return()=>{active=false;destroy?.();node.removeAttribute('src');node.load()}
 },[source,revision]);
 return <>{failed&&<p role="alert">Não foi possível reproduzir. Confira a conexão. <button type="button" onClick={()=>setRevision(v=>v+1)}>Tentar novamente</button></p>}<video ref={video} aria-label={title} controls playsInline preload="metadata" poster={mediaHttps(poster)||undefined} style={{width:'100%',maxHeight:'70vh',background:'#080d13',borderRadius:12}} onError={()=>setFailed(true)} onLoadedMetadata={e=>{if(start>0&&Number.isFinite(e.currentTarget.duration))e.currentTarget.currentTime=Math.min(start,Math.max(0,e.currentTarget.duration-1))}} onTimeUpdate={e=>{const position=Math.floor(e.currentTarget.currentTime);if(Math.abs(position-last.current)>=15){last.current=position;onProgress?.(position)}}} onPause={e=>onProgress?.(Math.floor(e.currentTarget.currentTime))}>Seu navegador não oferece reprodução deste vídeo.</video></>;
}
