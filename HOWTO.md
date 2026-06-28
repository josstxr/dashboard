# Guía rápida de uso del monitor

## 1. Iniciar el sistema

Ejecuta:

```bash
npm start
```

Luego abre la URL:

```text
http://127.0.0.1:4174
```

## 2. Iniciar sesión

Usa uno de los usuarios predefinidos:

- Usuario: `admin`
- Contraseña: `admin`

También puedes crear nuevos usuarios desde la sección de administración si tienes permisos.

## 3. Gestionar servicios

Desde la vista principal puedes:

- Levantar servicios
- Detener servicios
- Reiniciar servicios
- Ver logs
- Ejecutar scripts

## 4. Ejecutar consultas o scripts

1. Selecciona el servicio de base de datos.
2. Escribe el script o consulta.
3. Haz clic en Ejecutar.

## 5. Administrar usuarios

En la sección de administración puedes:

- Crear usuarios
- Editar permisos
- Asignar servicios
- Eliminar usuarios

## 6. Configurar nuevos SGBD

Si deseas agregar soporte para otro motor de base de datos, debes ajustar la configuración en [server/index.js](server/index.js) y, si es necesario, el archivo Compose para incluir el contenedor correspondiente.
