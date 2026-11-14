import {useState} from 'react';
import {ActivityIndicator,Image,KeyboardAvoidingView,Linking,Platform,Pressable,ScrollView,StyleSheet,Text,TextInput,View,useWindowDimensions} from 'react-native';
import {StatusBar} from 'expo-status-bar';
import {onBrand} from './experience-model';
import {loginProblems,signupProblems} from '../../shared/login-rules';
import {formatRegistrationField} from '../../shared/brazil-registration';
import ChurchSelect from './ChurchSelect';

type Props={appName:string;churchName:string;logo?:string|null;brand:string;dark:boolean;ready:boolean;busy:boolean;notice:string;
 email:string;setEmail:(v:string)=>void;password:string;setPassword:(v:string)=>void;signup:boolean;setSignup:(v:boolean)=>void;
 onSubmit:()=>void;onForgot:()=>void;onExplore:()=>void;onRetry?:()=>void;
 churches:{id:string;name:string}[];name:string;setName:(v:string)=>void;phone:string;setPhone:(v:string)=>void;unit:string;setUnit:(v:string)=>void};

/** Entrada e criação de conta (identidade Vinha): capa na cor da igreja, escolha Entrar/Criar conta, senha com mostrar e dicas claras. */
export default function LoginScreen(p:Props){
 const {width}=useWindowDimensions(),dark=p.dark,bg=dark?'#080f15':'#f2f6f8',surface=dark?'#111e28':'#ffffff',fg=dark?'#eff6fa':'#172d3b',muted=dark?'#adc0cc':'#4e6472',line=dark?'#2c414f':'#d8e3e9',onB=onBrand(p.brand);
 const [show,setShow]=useState(false),[tried,setTried]=useState(false),[confirm,setConfirm]=useState(''),[terms,setTerms]=useState(false);
 const problems=p.signup?signupProblems({name:p.name,phone:p.phone,unit:p.unit,email:p.email,password:p.password,confirm,terms}):loginProblems(p.email,p.password);
 const submit=()=>{setTried(true);if(!problems.length)p.onSubmit()};
 const tab=(label:string,on:boolean,press:()=>void)=><Pressable accessibilityRole="tab" accessibilityState={{selected:on}} onPress={press} style={[s.tab,on&&{backgroundColor:surface}]}><Text style={{color:on?fg:onB,fontWeight:'800',textAlign:'center'}}>{label}</Text></Pressable>;
 const label=(t:string)=><Text style={[s.label,{color:fg}]}>{t}</Text>;
 return <KeyboardAvoidingView style={{flex:1,backgroundColor:bg}} behavior={Platform.OS==='ios'?'padding':undefined}><StatusBar style="light"/>
  <ScrollView contentContainerStyle={{flexGrow:1}} keyboardShouldPersistTaps="handled">
   <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/><View style={[s.blob2,{backgroundColor:onB,opacity:.06}]}/>
    <View style={[s.inner,width>=700&&{maxWidth:520,alignSelf:'center',width:'100%'}]}>
     {p.logo?<View style={[s.logoBox,{backgroundColor:onB+'1f'}]}><Image accessibilityLabel="Logo da igreja" source={{uri:p.logo}} style={s.logo}/></View>:<View style={[s.logoBox,{backgroundColor:onB+'1f'}]}><Text style={{color:onB,fontWeight:'900',fontSize:22}}>{p.appName.slice(0,3).toUpperCase()}</Text></View>}
     <Text style={[s.over,{color:onB}]}>{p.churchName?p.churchName.toUpperCase():'CARREGANDO…'}</Text>
     <Text style={[s.title,{color:onB}]}>{p.signup?'Faça parte por aqui':'Que bom ver você'}</Text>
     <Text style={{color:onB,opacity:.88,marginTop:6,lineHeight:22}}>{p.signup?'Crie sua conta para se inscrever em eventos, pedir oração e acompanhar sua igreja.':'Entre para ver suas inscrições, pedidos e a agenda da sua igreja.'}</Text>
     <View style={[s.tabs,{backgroundColor:onB+'22'}]}>{tab('Entrar',!p.signup,()=>{setTried(false);p.setSignup(false)})}{tab('Criar conta',p.signup,()=>{setTried(false);p.setSignup(true)})}</View>
    </View>
   </View>
   <View style={[s.inner,{paddingTop:20},width>=700&&{maxWidth:520,alignSelf:'center',width:'100%'}]}>
    {p.notice!==''&&<Text accessibilityRole="alert" style={[s.notice,{color:fg,borderColor:line,backgroundColor:surface}]}>{p.notice}</Text>}
    {!p.ready?<View style={{padding:30}}><ActivityIndicator color={p.brand}/>{p.onRetry&&p.notice!==''&&<Pressable accessibilityRole="button" onPress={p.onRetry}><Text style={{color:fg,fontWeight:'800',textAlign:'center',marginTop:16}}>Tentar de novo</Text></Pressable>}</View>:<View style={[s.card,{backgroundColor:surface,borderColor:line}]}>
     {p.signup&&<>
      <View style={{marginBottom:6}}><ChurchSelect churches={p.churches} value={p.unit} onChange={p.setUnit} color={fg} background={bg} accent={p.brand}/></View>
      {label('Nome completo')}
      <TextInput accessibilityLabel="Nome completo" autoCapitalize="words" autoComplete="name" value={p.name} onChangeText={p.setName} maxLength={160} placeholder="Como está no seu documento" placeholderTextColor={muted} style={[s.input,{color:fg,borderColor:line,backgroundColor:bg}]}/>
      {label('WhatsApp')}
      <TextInput accessibilityLabel="WhatsApp com DDD" keyboardType="phone-pad" autoComplete="tel" value={formatRegistrationField('phone',p.phone)} onChangeText={v=>p.setPhone(formatRegistrationField('phone',v))} maxLength={20} placeholder="(16) 99999-9999" placeholderTextColor={muted} style={[s.input,{color:fg,borderColor:line,backgroundColor:bg}]}/>
     </>}
     {label('E-mail')}
     <TextInput accessibilityLabel="E-mail" autoCapitalize="none" autoComplete="email" keyboardType="email-address" value={p.email} onChangeText={p.setEmail} placeholder="voce@exemplo.com" placeholderTextColor={muted} style={[s.input,{color:fg,borderColor:line,backgroundColor:bg}]}/>
     {label(p.signup?'Crie uma senha':'Senha')}
     <View style={[s.passRow,{borderColor:line,backgroundColor:bg}]}><TextInput accessibilityLabel="Senha" secureTextEntry={!show} autoComplete={p.signup?'new-password':'current-password'} value={p.password} onChangeText={p.setPassword} placeholder={p.signup?'Pelo menos 8 caracteres':'Sua senha'} placeholderTextColor={muted} style={[s.passInput,{color:fg}]}/><Pressable accessibilityRole="button" accessibilityLabel={show?'Esconder senha':'Mostrar senha'} onPress={()=>setShow(!show)} style={s.eye}><Text style={{color:fg,fontWeight:'800'}}>{show?'Esconder':'Mostrar'}</Text></Pressable></View>
     {p.signup?<>
      {label('Repita a senha')}
      <TextInput accessibilityLabel="Repita a senha" secureTextEntry={!show} autoComplete="new-password" value={confirm} onChangeText={setConfirm} placeholder="Digite a mesma senha" placeholderTextColor={muted} style={[s.input,{color:fg,borderColor:line,backgroundColor:bg}]}/>
      <Pressable accessibilityRole="checkbox" accessibilityState={{checked:terms}} onPress={()=>setTerms(!terms)} style={s.termsRow}><View style={[s.box,{borderColor:terms?p.brand:muted,backgroundColor:terms?p.brand:'transparent'}]}>{terms&&<Text style={{color:onB,fontWeight:'900',fontSize:12}}>✓</Text>}</View><Text style={{color:muted,flex:1,lineHeight:20}}>Li e aceito os <Text accessibilityRole="link" onPress={()=>void Linking.openURL('https://app.vinhaigrejas.com.br/termos')} style={{color:fg,fontWeight:'800',textDecorationLine:'underline'}}>termos de uso</Text> e a <Text accessibilityRole="link" onPress={()=>void Linking.openURL('https://app.vinhaigrejas.com.br/privacidade')} style={{color:fg,fontWeight:'800',textDecorationLine:'underline'}}>política de privacidade</Text>.</Text></Pressable>
     </>:<Pressable accessibilityRole="button" onPress={p.onForgot} style={{alignSelf:'flex-end',paddingVertical:6}}><Text style={{color:fg,fontWeight:'700',textDecorationLine:'underline'}}>Esqueci minha senha</Text></Pressable>}
     {tried&&problems.length>0&&<View accessibilityRole="alert" style={[s.problems,{borderColor:'#e0a23a',backgroundColor:'#e0a23a1f'}]}>{problems.map(t=><Text key={t} style={{color:fg,lineHeight:21}}>•  {t}</Text>)}</View>}
     <Pressable accessibilityRole="button" accessibilityState={{disabled:p.busy}} disabled={p.busy} onPress={submit} style={[s.primary,{backgroundColor:p.brand,opacity:p.busy?.6:1}]}>{p.busy?<ActivityIndicator color={onB}/>:<Text style={{color:onB,fontWeight:'900',fontSize:16}}>{p.signup?'Criar minha conta':'Entrar'}</Text>}</Pressable>
     {p.signup&&<Text style={{color:muted,fontSize:13,marginTop:10,lineHeight:19}}>Vamos enviar um link para confirmar o e-mail. Endereço, documento e outros dados você completa depois, dentro do app.</Text>}
    </View>}
    <Pressable accessibilityRole="button" onPress={p.onExplore} style={[s.ghost,{borderColor:line}]}><Text style={{color:fg,fontWeight:'800'}}>Conhecer o app sem entrar</Text></Pressable>
    <Text style={[s.footer,{color:muted}]}>Feito com Vinha</Text>
   </View>
  </ScrollView>
 </KeyboardAvoidingView>;
}
const s=StyleSheet.create({
 cover:{paddingTop:56,paddingBottom:22,borderBottomLeftRadius:32,borderBottomRightRadius:32,overflow:'hidden'},
 blob:{position:'absolute',width:260,height:260,borderRadius:130,right:-90,top:-90},blob2:{position:'absolute',width:160,height:160,borderRadius:80,left:-60,bottom:-70},
 inner:{paddingHorizontal:22},logoBox:{width:72,height:72,borderRadius:22,alignItems:'center',justifyContent:'center',marginBottom:16},logo:{width:56,height:56,resizeMode:'contain'},
 over:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},title:{fontSize:28,fontWeight:'900',marginTop:6},
 tabs:{flexDirection:'row',borderRadius:18,padding:4,marginTop:20},tab:{flex:1,borderRadius:14,paddingVertical:11},
 card:{borderWidth:1,borderRadius:24,padding:18},label:{fontSize:14,fontWeight:'800',marginBottom:6},
 input:{borderWidth:1,borderRadius:14,minHeight:50,paddingHorizontal:14,fontSize:16,marginBottom:14},
 passRow:{flexDirection:'row',alignItems:'center',borderWidth:1,borderRadius:14,minHeight:50,marginBottom:10},passInput:{flex:1,minWidth:0,width:0,paddingHorizontal:14,fontSize:16,minHeight:50},eye:{paddingHorizontal:14,minHeight:44,justifyContent:'center'},
 problems:{borderWidth:1,borderRadius:14,padding:12,marginTop:6,gap:2},termsRow:{flexDirection:'row',gap:10,alignItems:'flex-start',marginBottom:6,marginTop:4},box:{width:22,height:22,borderRadius:7,borderWidth:2,alignItems:'center',justifyContent:'center',marginTop:1},
 primary:{borderRadius:16,minHeight:54,alignItems:'center',justifyContent:'center',marginTop:12},
 ghost:{borderWidth:1,borderRadius:16,minHeight:50,alignItems:'center',justifyContent:'center',marginTop:16},
 notice:{borderWidth:1,borderRadius:14,padding:14,marginBottom:14,lineHeight:22},footer:{textAlign:'center',fontSize:12,marginTop:24,marginBottom:30},
});
