# Dashboard de Monitor de Contenedores y Bases de Datos

Este proyecto ofrece una interfaz web para monitorear contenedores Docker, ejecutar scripts contra servicios de bases de datos y administrar usuarios con permisos configurables.

## Características

- Monitoreo de servicios Docker definidos en un archivo Compose.
- Ejecución de scripts SQL/NoSQL para distintos motores de base de datos.
- Gestión de usuarios y permisos por rol.
- Soporte para múltiples SGBD configurables.

## Requisitos

- Node.js 18 o superior
- Docker y Docker Compose
- Acceso a los contenedores que se desean administrar

## Instalación

1. Clona el repositorio:
   ```bash
   git clone <url-del-repositorio>
   cd dashboard
   ```

2. Instala las dependencias:
   ```bash
   npm install
   ```

3. Asegúrate de tener un archivo de Compose válido y ajusta la ruta en la variable de entorno `COMPOSE_FILE` si es necesario.

4. Inicia la aplicación:
   ```bash
   npm start
   ```

5. Abre la interfaz en:
   ```text
   http://127.0.0.1:4174
   ```

## Configuración

### Archivo de Compose

El monitor utiliza un archivo Compose para detectar servicios y controlar contenedores. Puedes definir la ruta del archivo con:

```bash
COMPOSE_FILE=/ruta/a/tu/docker-compose.yml
```

### Configuración de SGBD

El proyecto puede adaptarse a distintos motores de bases de datos mediante el catálogo configurado en el servidor. Los motores soportados por defecto incluyen:

- MySQL
- PostgreSQL
- MongoDB
- Cassandra
- SQL Server

Si necesitas agregar otro motor, puedes extender la configuración en el archivo [server/index.js](server/index.js) ajustando:

- `serviceCatalog`
- `permissionTemplates`
- `dbExecArgs`

### Usuarios y permisos

Los usuarios se almacenan en [server/users.json](server/users.json). Puedes editar este archivo para definir usuarios, contraseñas y permisos o administrarlos desde la interfaz.

## Variables de entorno

- `PORT`: Puerto del servidor web (por defecto 4174)
- `HOST`: Host de escucha (por defecto 127.0.0.1)
- `COMPOSE_FILE`: Ruta al archivo Compose a usar

## Solución de problemas

- Si Docker no responde, verifica que el daemon esté activo.
- Si no aparecen servicios, revisa que el archivo Compose sea válido.
- Si un script falla, confirma que el contenedor y el cliente del motor correspondiente estén disponibles.
