const path=require('node:path');
const {getDefaultConfig}=require('expo/metro-config');
const config=getDefaultConfig(__dirname);
config.watchFolders=[path.resolve(__dirname,'../shared')];
// Shared hooks must use this renderer's React, not the web application's copy.
config.resolver.resolveRequest=(context,moduleName,platform)=>context.resolveRequest(
 moduleName==='react'||moduleName.startsWith('react/')?{...context,originModulePath:path.join(__dirname,'index.ts')}:context,
 moduleName,platform
);
module.exports=config;
