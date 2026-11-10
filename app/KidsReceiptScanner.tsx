"use client";
import {useEffect,useRef,useState} from 'react';
type Detector={detect:(video:HTMLVideoElement)=>Promise<{rawValue:string}[]>};
type DetectorConstructor=new(options:{formats:string[]})=>Detector;
export default function KidsReceiptScanner({onCode}:{onCode:(code:string)=>void}){
 const video=useRef<HTMLVideoElement>(null),stream=useRef<MediaStream|null>(null),[active,setActive]=useState(false),[notice,setNotice]=useState('');
 useEffect(()=>{if(!active)return;let live=true,timer:ReturnType<typeof setTimeout>;const Detector=(window as unknown as {BarcodeDetector?:DetectorConstructor}).BarcodeDetector;
 async function start(){try{if(!Detector||!window.isSecureContext)throw Error('Leitura por câmera indisponível neste navegador. Cole o código completo no campo abaixo.');const media=await navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'},audio:false});if(!live){media.getTracks().forEach(t=>t.stop());return}stream.current=media;const node=video.current;if(!node)throw Error('Câmera indisponível.');node.srcObject=media;await node.play();const detector=new Detector({formats:['qr_code']});const scan=async()=>{if(!live)return;try{const result=await detector.detect(node);const code=result.map(v=>v.rawValue.trim().toLowerCase()).find(v=>/^[a-f0-9]{64}$/.test(v));if(code){onCode(code);setNotice('Código lido. Confira o responsável e confirme a retirada no formulário.');setActive(false);return}}catch{}if(live)timer=setTimeout(()=>void scan(),350)};void scan()}catch(e){if(live){setNotice(e instanceof Error?e.message:'Não foi possível abrir a câmera. Cole o código.');setActive(false)}}}
 void start();const timeout=setTimeout(()=>{if(live){setNotice('Leitura encerrada. Tente novamente ou cole o código.');setActive(false)}},60000);
 return()=>{live=false;clearTimeout(timer);clearTimeout(timeout);stream.current?.getTracks().forEach(t=>t.stop());stream.current=null};
 // The callback only fills the existing field; custody requires its original confirmation.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[active]);
 return <section aria-label="Ler comprovante por câmera">{active&&<video ref={video} playsInline muted style={{width:'100%',maxHeight:220}}/>}<button type="button" onClick={()=>setActive(v=>!v)}>{active?'Fechar câmera':'Ler QR do comprovante'}</button>{notice&&<p role="status">{notice}</p>}</section>
}
