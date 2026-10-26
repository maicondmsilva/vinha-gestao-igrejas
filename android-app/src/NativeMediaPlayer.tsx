import {useEffect,useRef,useState} from 'react';
import {AppState,Pressable,Text,View} from 'react-native';
import {VideoView,useVideoPlayer} from 'expo-video';
import Constants from 'expo-constants';
import {WebView} from 'react-native-webview';
import {mediaSource} from '../../shared/ministry-media';
export default function NativeMediaPlayer({source,title,start=0,onProgress,color='#173b30'}:{source:string;title:string;start?:number;onProgress?:(seconds:number)=>void;color?:string}){
 const media=source.startsWith('file://')?{kind:'direct',url:source,embed:source}:mediaSource(source),[play,setPlay]=useState(false);
 if(!media)return <Text style={{color}}>Formato de reprodução indisponível.</Text>;
 if(media.kind==='direct')return <DirectPlayer key={media.url} source={media.url} title={title} start={start} onProgress={onProgress} color={color}/>;
 return play?<WebView source={{uri:media.embed,headers:{Referer:'https://'+(Constants.expoConfig?.android?.package||'com.vinha.mpr.preview')}}} style={{height:230,backgroundColor:'#080e15'}} javaScriptEnabled domStorageEnabled allowsFullscreenVideo mediaPlaybackRequiresUserAction setSupportMultipleWindows={false} onShouldStartLoadWithRequest={r=>{try{return r.url==='about:blank'||['www.youtube-nocookie.com','www.youtube.com','youtube.com','player.vimeo.com'].includes(new URL(r.url).hostname)}catch{return false}}}/>:<View><Text style={{color,marginVertical:10}}>Este vídeo usa {media.kind==='youtube'?'YouTube':'Vimeo'}. O player será carregado ao continuar.</Text><Pressable accessibilityRole="button" onPress={()=>setPlay(true)} style={{padding:16,borderWidth:1,borderColor:color,borderRadius:10}}><Text style={{color}}>Reproduzir {title}</Text></Pressable></View>;
}
function DirectPlayer({source,title,start,onProgress,color}:{source:string;title:string;start:number;onProgress?: (seconds:number)=>void;color:string}){
 const [failed,setFailed]=useState(false),last=useRef(0),callback=useRef(onProgress);callback.current=onProgress;
 const player=useVideoPlayer({uri:source,contentType:/\.m3u8(?:\?|$)/i.test(source)?'hls':'progressive'},p=>{p.timeUpdateEventInterval=1;p.currentTime=Math.max(0,start);p.loop=false});
 useEffect(()=>{const a=player.addListener('timeUpdate',e=>{const seconds=Math.floor(e.currentTime);if(Math.abs(seconds-last.current)>=15){last.current=seconds;callback.current?.(seconds)}}),b=player.addListener('statusChange',e=>{if(e.status==='error')setFailed(true)}),state=AppState.addEventListener('change',s=>{if(s!=='active')player.pause()});return()=>{a.remove();b.remove();state.remove()}},[player]);
 if(failed)return <Text accessibilityRole="alert" style={{color}}>Não foi possível reproduzir. Confira a conexão e abra novamente o vídeo.</Text>;
 return <VideoView player={player} nativeControls contentFit="contain" surfaceType="textureView" fullscreenOptions={{enable:true}} accessibilityLabel={'Reprodutor: '+title} style={{height:230,width:'100%',backgroundColor:'#080e15',borderRadius:12}}/>;
}
