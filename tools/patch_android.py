#!/usr/bin/env python3
"""Parcha el proyecto Android que genera `flutter create`.

Uso: python3 patch_android.py RUTA_DEL_PROYECTO

- minSdk 24
- nombre visible "Aztra Analyzer"
- permisos (audio, notificaciones, servicio en primer plano)
- servicio de analisis en segundo plano (Kotlin) + MainActivity con canal
- icono chico de notificacion
"""
import glob
import os
import re
import shutil
import sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
APP_NAME = 'Aztra Analyzer'

# 1) minSdk -------------------------------------------------------------------
for name in ('build.gradle', 'build.gradle.kts'):
    path = os.path.join(root, 'android', 'app', name)
    if os.path.isfile(path):
        text = open(path, encoding='utf-8').read()
        new = text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        new = new.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
        open(path, 'w', encoding='utf-8').write(new)
        print('minSdk ajustado en', name, '->', 'minSdk = 24' in new or 'minSdkVersion 24' in new)

# 2) Kotlin: MainActivity + servicio ------------------------------------------
found = glob.glob(os.path.join(root, 'android', 'app', 'src', 'main', '**', 'MainActivity.kt'), recursive=True)
if not found:
    sys.exit('ERROR: no encontre MainActivity.kt')
main_path = found[0]
kotlin_dir = os.path.dirname(main_path)
first = open(main_path, encoding='utf-8').read()
m = re.search(r'^package\s+([\w.]+)', first, re.M)
if not m:
    sys.exit('ERROR: no pude leer el package de MainActivity.kt')
pkg = m.group(1)
print('package:', pkg)

for fname in ('MainActivity.kt', 'AnalysisService.kt'):
    src = open(os.path.join(here, 'android', fname), encoding='utf-8').read()
    src = src.replace('package PLACEHOLDER', 'package ' + pkg, 1)
    open(os.path.join(kotlin_dir, fname), 'w', encoding='utf-8').write(src)
    print('escrito', os.path.join(kotlin_dir, fname))

# 3) Manifest -----------------------------------------------------------------
manifest_path = os.path.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
text = open(manifest_path, encoding='utf-8').read()

text, n = re.subn(r'android:label="[^"]*"', 'android:label="%s"' % APP_NAME, text, count=1)
print('label cambiado:', n == 1)

perms = [
    ('android.permission.READ_MEDIA_AUDIO', ''),
    ('android.permission.READ_EXTERNAL_STORAGE', ' android:maxSdkVersion="32"'),
    ('android.permission.MANAGE_EXTERNAL_STORAGE', ''),
    ('android.permission.POST_NOTIFICATIONS', ''),
    ('android.permission.FOREGROUND_SERVICE', ''),
    ('android.permission.FOREGROUND_SERVICE_DATA_SYNC', ''),
    ('android.permission.WAKE_LOCK', ''),
]
lines = ''
for name, extra in perms:
    if name not in text:
        lines += '    <uses-permission android:name="%s"%s/>\n' % (name, extra)
idx = text.find('<application')
if idx < 0:
    sys.exit('ERROR: no encontre <application en el manifest')
text = text[:idx] + lines.lstrip() + '    ' + text[idx:]

service = (
    '        <service\n'
    '            android:name="%s.AnalysisService"\n'
    '            android:exported="false"\n'
    '            android:foregroundServiceType="dataSync"\n'
    '            android:stopWithTask="true" />\n'
) % pkg
close = text.rfind('</application>')
if close < 0:
    sys.exit('ERROR: no encontre </application>')
text = text[:close] + service + '    ' + text[close:]
open(manifest_path, 'w', encoding='utf-8').write(text)

# 4) Icono de notificacion ----------------------------------------------------
res_src = os.path.join(here, 'android_res')
res_dst = os.path.join(root, 'android', 'app', 'src', 'main', 'res')
for d in os.listdir(res_src):
    dst = os.path.join(res_dst, d)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(os.path.join(res_src, d)):
        shutil.copy(os.path.join(res_src, d, f), os.path.join(dst, f))
print('iconos de notificacion copiados')
print('--- manifest final ---')
print(text)
