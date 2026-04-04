# KPEG — Contexto del Proyecto

## ¿Qué es KPEG?
App Android que abre la cámara, hace una foto y la envía a una API REST.

## Stack tecnológico
- **App:** Flutter (Dart) — proyecto en `AndroidApp/kpeg_app/`
- **API:** Python + Flask — proyecto en `API/api.py`

## Entorno de desarrollo
- Ubuntu 22.04 desktop
- Flutter 3.41.6 (stable) — instalado en `/home/jmaria/Flutter/flutter`
- Android Studio Panda3 — instalado en `/home/jmaria/android-studio-panda3-linux/android-studio`
- Android SDK — en `/home/jmaria/Android/Sdk`
- Shell: zsh

## Estructura del repositorio
```
KPEG/
├── AndroidApp/
│   └── kpeg_app/          # Proyecto Flutter
│       ├── lib/main.dart  # Código principal de la app
│       ├── pubspec.yaml   # Dependencias Flutter
│       └── android/       # Configuración Android
├── API/
│   ├── api.py             # API Flask
│   └── requirements.txt
├── Presentation/
├── Tooling/
└── CONTEXT.md
```

## Dependencias Flutter (pubspec.yaml)
- `image_picker: ^1.1.2` — para abrir la cámara
- `http: ^1.2.1` — para enviar la foto a la API

## Configuración crítica Android

### AndroidManifest.xml
Ubicación: `android/app/src/main/AndroidManifest.xml`

Debe contener obligatoriamente:
- `<meta-data android:name="flutterEmbedding" android:value="2"/>` dentro de `<application>` (obligatorio para Flutter 3.41.6)
- Permiso `CAMERA` e `INTERNET`
- `android:usesCleartextTraffic="true"` (para HTTP local)
- `FileProvider` configurado apuntando a `@xml/file_paths`

### file_paths.xml
Ubicación: `android/app/src/main/res/xml/file_paths.xml`
Requerido por el paquete `image_picker`.

### local.properties
Ubicación: `android/local.properties`
**No subir a git** (está en .gitignore).
Contenido:
```
sdk.dir=/home/jmaria/Android/Sdk
flutter.sdk=/home/jmaria/Flutter/flutter
```

## Problemas resueltos y sus soluciones

### 1. "Build failed due to use of deleted Android v1 embedding"
- **Causa:** Flutter 3.41.6 requiere declarar explícitamente `flutterEmbedding=2` en el AndroidManifest. Si no está presente, Flutter asume v1 automáticamente (ver `computeEmbeddingVersion()` en `project.dart` línea 1015).
- **Solución:** Añadir dentro de `<application>` en el AndroidManifest:
```xml
<meta-data
    android:name="flutterEmbedding"
    android:value="2"/>
```

### 2. `local.properties` con `%` al final de la ruta
- **Causa:** El heredoc de zsh añadió un carácter `%` extra al final.
- **Solución:** Reescribir el archivo directamente con `cat >` en lugar de `echo`.

### 3. APK demasiado grande para GitHub (160MB)
- **Causa:** El APK debug incluye símbolos de depuración y todas las arquitecturas.
- **Solución:** Añadir `*.apk` al `.gitignore`. Para limpiar historial usar `git filter-branch`. Para APK ligero usar `flutter build apk --release --split-per-abi`.

### 4. Emulador Android no accede a localhost del PC
- **Solución:** Usar `10.0.2.2` en lugar de `localhost` o `127.0.0.1`.

### 5. Móvil físico no accede al PC (puertos 8000/9000)
- **Causa:** Firewall UFW activo bloqueaba los puertos.
- **Solución:** `sudo ufw allow 8000 && sudo ufw allow 9000`

### 6. `studio foto_app` abría un archivo en lugar del proyecto
- **Solución:** Ejecutar `studio .` desde dentro de la carpeta del proyecto.

### 7. Carpeta `java` con `GeneratedPluginRegistrant.java` causaba error v1
- **Solución:** `rm -rf android/app/src/main/java`

## API local

- **Puerto:** 8000
- **Endpoint upload:** `POST http://<IP>:8000/upload`
- **Campo del archivo:** `foto` (multipart/form-data)
- **Las fotos se guardan en:** `API/fotos/`
- **Endpoint status:** `GET http://<IP>:8000/` — devuelve JSON con número de fotos recibidas
- **Arrancar:** `python3 API/api.py`

## URLs según entorno
- **Emulador Android:** `http://10.0.2.2:8000/upload`
- **Móvil físico (misma WiFi):** `http://10.105.176.246:8000/upload`

> ⚠️ La IP `10.105.176.246` puede cambiar si el router reasigna DHCP. Verificar con `ip a` antes de compilar para móvil físico.

## Diseño de la app
- Tema: **dark** con color primario verde `#00C896`
- Fondo: gradiente `#0A0A0A → #0D1F1A → #0A1628`
- Flujo de usuario:
  1. Pantalla inicial con área de previsualización vacía
  2. Botón **"Hacer foto"** → abre cámara nativa
  3. Preview de la foto en la pantalla
  4. Botón **"Enviar foto"** → envía a la API con feedback visual
  5. Indicador de estado: enviando / éxito / error

## Comandos útiles

```bash
# Ejecutar en emulador
cd AndroidApp/kpeg_app && flutter run

# Generar APK release ligero (recomendado)
flutter build apk --release --split-per-abi
# APK para móviles modernos: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Servir APK por HTTP para instalarlo en móvil físico
cd build/app/outputs/flutter-apk/
python3 -m http.server 9000
# Acceder desde móvil: http://10.105.176.246:9000

# Instalar dependencias API
pip install flask

# Abrir Android Studio en el proyecto
cd AndroidApp/kpeg_app && studio .

# Verificar IP local del PC
ip a | grep "inet " | grep -v "127.0.0.1"

# Abrir puertos en el firewall
sudo ufw allow 8000
sudo ufw allow 9000

# Limpiar y recompilar Flutter
flutter clean && flutter pub get && flutter run
```

## .gitignore importante
```
*.apk
android/local.properties
```

## Estado actual del proyecto
- ✅ App Flutter funcional con diseño dark + verde
- ✅ Cámara nativa funcionando con `image_picker`
- ✅ Envío de foto a API via `multipart/form-data`
- ✅ API Python/Flask recibiendo y guardando fotos en carpeta `fotos/`
- ✅ Probada en emulador Android
- ✅ Probada en móvil físico Android real
- ✅ APK release generado e instalado en móvil físico
- ✅ Repositorio GitHub limpio y organizado
