import {useState} from 'react';
import {Image,Linking,Pressable,Share,Text,TextInput,View} from 'react-native';
import QrCode from './QrCode';
import {onBrand,brandColor} from './experience-model';
import * as Crypto from 'expo-crypto';
import {supabase} from './supabase';
import type {ChurchRpc} from '../../shared/member-church';
import {useMemberServices} from '../../shared/use-member-services';
import {memberAmount,memberMoney,paymentStates,trustedPaymentUrl} from '../../shared/member-services';
type Palette={surface:string;text:string;muted:string;line:string;brand:string};
export default function ServicesScreen({rpc,org,unit,authenticated,palette:p,kind}:{rpc:ChurchRpc;org:string;unit:string;authenticated:boolean;palette:Palette;kind:'payments'|'cards'}){
 const m=useMemberServices(rpc,org,unit,authenticated),[purpose,setPurpose]=useState(''),[amount,setAmount]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[nonce,setNonce]=useState('');
 const button=(label:string,action:()=>void,disabled=false)=><Pressable accessibilityRole="button" accessibilityState={{disabled:disabled||busy||m.busy}} disabled={disabled||busy||m.busy} onPress={action} style={{padding:14,marginVertical:7,borderWidth:1,borderColor:p.brand,borderRadius:10}}><Text style={{color:p.text,fontWeight:'600'}}>{label}</Text></Pressable>;
 async function checkout(id:string,orderUnit:string){setBusy(true);setNotice('');try{const s=await supabase!.auth.getSession();if(!s.data.session)throw Error('Entre novamente.');const r=await fetch('https://app.vinhaigrejas.com.br/api/member-payments',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+s.data.session.access_token},body:JSON.stringify({org,unit:orderUnit,id})}),d=await r.json();if(!r.ok)throw Error(d.error);const url=trustedPaymentUrl(d.checkoutUrl);if(url)await Linking.openURL(url);else setNotice('Atualize o histórico para consultar o estado do pagamento.')}catch(e){setNotice(e instanceof Error?e.message:'Não confirmado. Consulte o histórico.')}finally{setBusy(false);m.refresh()}}
 if(!authenticated)return <Text style={{color:p.text}}>Entre na sua conta para consultar esta área.</Text>;
 return <View><Text accessibilityRole="header" style={{fontSize:24,fontWeight:'700',color:p.text}}>{kind==='payments'?'Contribua':'Minhas carteirinhas'}</Text>{m.error&&<Text accessibilityRole="alert" style={{color:p.text}}>{m.error}</Text>}{notice&&<Text accessibilityRole="alert" style={{color:p.text}}>{notice}</Text>}{kind==='payments'?<><Text style={{color:p.muted,marginVertical:14}}>Selecione a finalidade. O pagamento abre no ambiente seguro do provedor; a confirmação vem do financeiro.</Text><View style={{flexDirection:'row',flexWrap:'wrap',gap:10}}>{m.purposes.map(x=><Pressable key={x.id} accessibilityRole="button" accessibilityState={{selected:purpose===x.id,disabled:!!nonce}} disabled={!!nonce} onPress={()=>setPurpose(x.id)} style={{flexBasis:'47%',flexGrow:1,minHeight:96,borderRadius:16,padding:16,justifyContent:'flex-end',backgroundColor:purpose===x.id?p.brand:p.surface,borderWidth:1,borderColor:purpose===x.id?p.brand:p.line}}><Text style={{color:purpose===x.id?onBrand(p.brand):p.text,fontSize:18,fontWeight:'800'}}>{x.name}</Text><Text style={{color:purpose===x.id?onBrand(p.brand):p.muted,marginTop:4}}>{purpose===x.id?'Selecionado':'Tocar para escolher'}</Text></Pressable>)}</View><TextInput accessibilityLabel="Valor em reais" value={amount} editable={!nonce&&!busy} onChangeText={setAmount} keyboardType="decimal-pad" placeholder="Valor em reais" placeholderTextColor={p.muted} style={{color:p.text,padding:15,borderWidth:1,borderColor:p.line,borderRadius:10}}/>{button('Criar pedido de contribuição',()=>{const cents=memberAmount(amount);if(!cents||!purpose){setNotice('Selecione a finalidade e informe um valor a partir de R$ 1,00.');return}const id=nonce||Crypto.randomUUID();setNonce(id);void m.create(id,purpose,cents).then(ok=>{if(ok){setNonce('');setAmount('');setNotice('Pedido criado. Abra o pagamento pelo histórico.')}})},!m.purposes.length||!!nonce)}{nonce&&button('Conferir pedido sem confirmação',()=>{if(m.orders.some(o=>o.id===nonce))setNonce('');m.refresh()})}{!m.loading&&!m.purposes.length&&<Text style={{color:p.muted}}>Nenhuma finalidade com recebimento ativo publicada pela igreja.</Text>}<Text style={{fontSize:20,color:p.text,marginTop:20}}>Minhas contribuições</Text>{m.orders.map(o=><View key={o.id} style={{padding:16,borderWidth:1,borderColor:p.line,borderRadius:12,marginVertical:10}}><Text style={{color:p.text,fontWeight:'700'}}>{o.purpose} · {memberMoney(o.amount)}</Text><Text style={{color:p.muted}}>{paymentStates[o.status]||'Em conferência'}</Text><Text selectable style={{color:p.muted}}>Pedido {o.id}</Text>{o.status==='pending'&&button('Abrir ou retomar pagamento',()=>void checkout(o.id,o.unit_id))}</View>)}</>:<><Text style={{color:p.muted,marginVertical:14}}>A igreja emite a partir do cadastro oficial. Validade e revogação são conferidas pela equipe; não concede acesso aos módulos.</Text>{m.cards.map(c=>{const bg=brandColor(c.primary||p.brand),fg=onBrand(bg),logo=c.logo&&/^data:image\/png;base64,|^https:\/\//.test(c.logo)?c.logo:null;return <View key={c.id} style={{marginVertical:14}}>
  <View accessibilityLabel={'Carteirinha '+c.category+' de '+c.name} style={{backgroundColor:bg,borderRadius:18,padding:18,minHeight:210,opacity:c.valid?1:0.6}}>
   <View style={{flexDirection:'row',justifyContent:'space-between',alignItems:'flex-start',gap:10}}>
    {logo?<Image source={{uri:logo}} resizeMode="contain" style={{width:110,height:48}}/>:<Text style={{color:fg,fontWeight:'800',fontSize:16,flex:1}}>{c.ministry||''}</Text>}
    <View style={{borderWidth:1,borderColor:fg,borderRadius:14,paddingHorizontal:10,paddingVertical:4}}><Text style={{color:fg,fontWeight:'700',fontSize:12}}>{c.category}</Text></View>
   </View>
   <View style={{flexDirection:'row',alignItems:'flex-end',marginTop:18,gap:12}}>
    <View style={{flex:1}}>
     <Text style={{color:fg,opacity:.8,fontSize:11,fontWeight:'700',letterSpacing:1}}>NOME</Text>
     <Text style={{color:fg,fontSize:19,fontWeight:'800'}}>{c.name}</Text>
     <Text style={{color:fg,opacity:.8,fontSize:11,fontWeight:'700',letterSpacing:1,marginTop:10}}>IGREJA</Text>
     <Text style={{color:fg,fontSize:14}}>{c.unit}</Text>
     <Text style={{color:fg,opacity:.8,fontSize:11,fontWeight:'700',letterSpacing:1,marginTop:10}}>VALIDADE</Text>
     <Text style={{color:fg,fontSize:14}}>{c.expires.split('-').reverse().join('/')}{c.valid?'':' · sem validade'}</Text>
    </View>
    {c.valid&&c.code&&<QrCode value={c.code} size={104}/>}
   </View>
  </View>
  {c.valid&&c.code&&button('Compartilhar carteirinha',()=>void Share.share({message:[c.category,c.name,c.unit,'Validade: '+c.expires.split('-').reverse().join('/'),'Código de conferência: '+c.code].join('\n')}))}
 </View>})}{!m.loading&&!m.cards.length&&<Text style={{color:p.text}}>Nenhuma carteirinha emitida.</Text>}</>}{button('Atualizar',m.refresh)}</View>;
}
