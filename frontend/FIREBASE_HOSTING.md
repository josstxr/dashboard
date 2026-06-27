# Healthy-T en Firebase Hosting

Esta app ya queda preparada para desplegarse como Flutter Web en Firebase Hosting.

## Desplegar

```bash
flutter build web --release
firebase deploy --only hosting
```

Firebase Hosting publica el contenido de `build/web` y usa `index.html` como fallback para que la app no falle al recargar una ruta.

## Funciones disponibles en web

- Inicio de sesión con Supabase.
- Rutinas y dietas guardadas en Supabase/local.
- Importación de Excel/PDF desde el navegador.
- Asignación de rutinas y dietas a usuarios.
- Captura o selección de imágenes de dieta con IA, siempre que el navegador tenga permiso de cámara y Gemini tenga cuota disponible.
- PWA instalable desde el navegador.

## Funciones nativas que no existen en Firebase Hosting

Firebase Hosting sirve una web estática. Estas funciones siguen funcionando en iPhone cuando instales la app nativa, pero no pueden existir igual en navegador:

- Dynamic Island / Live Activities.
- Apple Health.
- Notificaciones locales nativas de iOS.
- Archivos guardados directamente al sistema sin diálogo del navegador.

## Antes de publicar

En Supabase agrega el dominio de Firebase en Authentication > URL Configuration:

- Site URL: `https://TU-PROYECTO.web.app`
- Redirect URLs:
  - `https://TU-PROYECTO.web.app/**`
  - `https://TU-PROYECTO.firebaseapp.com/**`

Si usas dominio propio, agrega también:

- `https://TU-DOMINIO/**`

