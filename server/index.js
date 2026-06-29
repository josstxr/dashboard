import http from "node:http";
import { execFile, spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import * as yaml from "js-yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const publicDir = path.join(rootDir, "public");

const PORT = Number(process.env.PORT || 4174);
const HOST = process.env.HOST || "127.0.0.1";

// --- CONFIGURACIÓN DEL PROYECTO DOCKER ---
// Esta es la ruta COMPLETA a tu archivo de compose.
// ¡Asegúrate de que esta ruta sea correcta!
const COMPOSE_FILE = process.env.COMPOSE_FILE || "/Users/jxsh/Desktop/contenedor-docker/db.yml";
const COMPOSE_DIR = path.dirname(COMPOSE_FILE);
const USERS_DB_FILE = path.join(__dirname, "users.json");

let USERS_DB = {};

async function loadUsersDb() {
  try {
    const content = await readFile(USERS_DB_FILE, "utf-8");
    const db = JSON.parse(content);
    // Valida que la estructura del archivo de usuarios sea la correcta, buscando el objeto de permisos.
    if (!db.users?.admin?.permissions || !db.users?.guest?.permissions) {
      throw new Error("Formato de users.json obsoleto o inválido. Se creará uno nuevo.");
    }
    USERS_DB = db;
  } catch (e) {
    console.log(`Info: ${e.message || "No se encontró users.json. Creando uno por defecto."}`);
    // Si el archivo no existe o es inválido, se crea uno por defecto.
    const adminPermissions = {
      allowedCompose: ["up", "stop", "restart", "down", "pull"],
      canQuery: true,
      canGetLogs: true,
      canSeeAllServices: true,
      canUsePermissionScripts: true,
      canManageUsers: true
    };
    const guestPermissions = {
      allowedCompose: [],
      canQuery: true,
      isSelectOnly: true,
      canGetLogs: false,
      canSeeAllServices: true,
      canUsePermissionScripts: false,
      canManageUsers: false
    };
    USERS_DB = {
      users: {
        admin: {
          password: "admin", // ¡ADVERTENCIA! Contraseña en texto plano. Usar hash en producción.
          permissions: adminPermissions
        },
        guest: { password: "guest", permissions: guestPermissions }
      },
      roles: {
        administrador: adminPermissions,
        gerente: {
          allowedCompose: ["up", "stop", "restart", "pull"],
          canQuery: true,
          canGetLogs: true,
          canSeeAllServices: true,
          canUsePermissionScripts: false,
          canManageUsers: false
        },
        trabajador: {
          allowedCompose: ["restart"],
          canQuery: false,
          canGetLogs: true,
          canSeeAllServices: false,
          canUsePermissionScripts: false,
          canManageUsers: false
        },
        invitado: guestPermissions
      }
    };
    await saveUsersDb();
  }
}

async function saveUsersDb() {
  await writeFile(USERS_DB_FILE, JSON.stringify(USERS_DB, null, 2), "utf-8");
}

const dbEngineCatalog = {
  mysql: {
    engine: "mysql",
    label: "MySQL",
    client: "mysql",
    defaultScript:
      "CREATE DATABASE IF NOT EXISTS escuela;\nUSE escuela;\nCREATE TABLE IF NOT EXISTS alumnos (id INT AUTO_INCREMENT PRIMARY KEY, nombre VARCHAR(80), carrera VARCHAR(80));\nINSERT INTO alumnos (nombre, carrera) VALUES ('Ana Torres', 'Sistemas');\nSELECT * FROM alumnos;",
    permissionTemplate:
      "CREATE USER IF NOT EXISTS 'lector'@'%' IDENTIFIED BY 'lector123';\nGRANT SELECT ON escuela.* TO 'lector'@'%';\nFLUSH PRIVILEGES;"
  },
  postgresql: {
    engine: "postgresql",
    label: "PostgreSQL",
    client: "psql",
    defaultScript:
      "CREATE TABLE IF NOT EXISTS alumnos (id SERIAL PRIMARY KEY, nombre TEXT, carrera TEXT);\nINSERT INTO alumnos (nombre, carrera) VALUES ('Ana Torres', 'Sistemas');\nSELECT * FROM alumnos;",
    permissionTemplate:
      "DO $$ BEGIN CREATE ROLE lector LOGIN PASSWORD 'lector123'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;\nGRANT CONNECT ON DATABASE dbejemplo TO lector;\nGRANT USAGE ON SCHEMA public TO lector;\nGRANT SELECT ON ALL TABLES IN SCHEMA public TO lector;"
  },
  mongodb: {
    engine: "mongodb",
    label: "MongoDB",
    client: "mongo",
    defaultScript:
      "db = db.getSiblingDB('escuela');\ndb.alumnos.insertOne({ nombre: 'Ana Torres', carrera: 'Sistemas', creado: new Date() });\ndb.alumnos.find().pretty();",
    permissionTemplate:
      "db = db.getSiblingDB('escuela');\ndb.createUser({ user: 'lector', pwd: 'lector123', roles: [{ role: 'read', db: 'escuela' }] });"
  },
  cassandra: {
    engine: "cassandra",
    label: "Cassandra",
    client: "cqlsh",
    defaultScript:
      "CREATE KEYSPACE IF NOT EXISTS escuela WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\nCREATE TABLE IF NOT EXISTS escuela.alumnos (id uuid PRIMARY KEY, nombre text, carrera text);\nINSERT INTO escuela.alumnos (id, nombre, carrera) VALUES (uuid(), 'Ana Torres', 'Sistemas');\nSELECT * FROM escuela.alumnos;",
    permissionTemplate:
      "CREATE ROLE IF NOT EXISTS lector WITH PASSWORD = 'lector123' AND LOGIN = true;\nGRANT SELECT ON KEYSPACE escuela TO lector;"
  },
  sqlserver: {
    engine: "sqlserver",
    label: "SQL Server",
    client: "sqlcmd",
    defaultScript:
      "IF DB_ID('escuela') IS NULL CREATE DATABASE escuela;\nGO\nUSE escuela;\nGO\nIF OBJECT_ID('dbo.alumnos', 'U') IS NULL CREATE TABLE dbo.alumnos (id INT IDENTITY(1,1) PRIMARY KEY, nombre NVARCHAR(80), carrera NVARCHAR(80));\nINSERT INTO dbo.alumnos (nombre, carrera) VALUES (N'Ana Torres', N'Sistemas');\nSELECT * FROM dbo.alumnos;\nGO",
    permissionTemplate:
      "USE escuela;\nGO\nIF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'lector') CREATE LOGIN lector WITH PASSWORD = 'Lector123!';\nIF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'lector') CREATE USER lector FOR LOGIN lector;\nALTER ROLE db_datareader ADD MEMBER lector;\nGO"
  }
};

const dbEngineImageMatchers = [
  { pattern: /mysql|mariadb/i, engine: "mysql" },
  { pattern: /postgres|postgresql/i, engine: "postgresql" },
  { pattern: /mongo/i, engine: "mongodb" },
  { pattern: /cassandra/i, engine: "cassandra" },
  { pattern: /mssql|sqlserver|microsoft\/mssql/i, engine: "sqlserver" }
];

function getEnvValue(environment, name) {
  if (!environment) return undefined;
  if (Array.isArray(environment)) {
    const item = environment.find((entry) => String(entry).startsWith(`${name}=`));
    return item?.split("=", 2)[1];
  }
  if (typeof environment === "object") {
    return environment[name] ?? environment[name.toUpperCase()] ?? environment[name.toLowerCase()];
  }
  return undefined;
}

function inferDbEngineFromImage(image) {
  const normalized = String(image || "").trim().toLowerCase();
  if (!normalized) return null;
  const match = dbEngineImageMatchers.find((item) => item.pattern.test(normalized));
  return match?.engine || null;
}

function getServiceMeta(service, serviceConfig = null, row = null) {
  if (Object.prototype.hasOwnProperty.call(dbEngineCatalog, service)) {
    return dbEngineCatalog[service];
  }

  const image = row?.Image || serviceConfig?.image || "";
  const engine = inferDbEngineFromImage(image);
  if (!engine) {
    return null;
  }
  return dbEngineCatalog[engine];
}

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    execFile(command, args, {
      cwd: options.cwd || COMPOSE_DIR,
      timeout: options.timeout || 120000,
      maxBuffer: 1024 * 1024 * 8
    }, (error, stdout, stderr) => {
      resolve({
        ok: !error,
        code: error?.code ?? 0,
        stdout: stdout?.trim() || "",
        stderr: stderr?.trim() || "",
        command: [command, ...args].join(" ")
      });
    });
  });
}

function composeArgs(args) {
  return ["-f", COMPOSE_FILE, ...args];
}

async function dockerCompose(args, options) {
  return run("docker-compose", composeArgs(args), options);
}

function sendJson(res, status, data) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function validateService(service) {
  const composeFileContent = await readFile(COMPOSE_FILE, "utf-8");
  const composeConfig = yaml.load(composeFileContent);
  const allServiceNames = Object.keys(composeConfig.services || {});
  if (!allServiceNames.includes(service)) {
    throw new Error(`Servicio no encontrado en ${COMPOSE_FILE}: ${service}`);
  }
}

function normalizePs(stdout) {
  if (!stdout) return [];
  return stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value >= 10 || unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unitIndex]}`;
}

async function getHostResources() {
  const totalMemory = os.totalmem();
  const freeMemory = os.freemem();
  const usedMemory = totalMemory - freeMemory;
  const diskResult = await run("df", ["-Pk", "/"], { timeout: 15000 });

  let disk = { total: 0, used: 0, free: 0, percent: 0 };
  if (diskResult.ok) {
    const lines = diskResult.stdout.split("\n").filter(Boolean);
    if (lines.length > 1) {
      const parts = lines[1].trim().split(/\s+/);
      const [, size, used, avail, percent] = parts;
      disk = {
        total: Number(size) * 1024,
        used: Number(used) * 1024,
        free: Number(avail) * 1024,
        percent: Number(percent.replace("%", "")) || 0
      };
    }
  }

  return {
    platform: os.platform(),
    arch: os.arch(),
    cpuCount: os.cpus().length,
    memory: {
      total: totalMemory,
      used: usedMemory,
      free: freeMemory,
      percent: Math.round((usedMemory / totalMemory) * 100)
    },
    disk
  };
}

async function getContainerResources(containers) {
  if (!containers?.length) return [];
  const result = await run("docker", ["stats", "--no-stream", "--format", "{{json .}}", ...containers], { timeout: 30000 });
  if (!result.ok) return [];

  return result.stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      try {
        const item = JSON.parse(line);
        return {
          name: String(item.Name || "").replace(/^\/+/, ""),
          cpuPercent: item.CPUPerc || null,
          memoryUsage: item.MemUsage || null,
          memoryPercent: item.MemPerc || null,
          networkIO: item.NetIO || null,
          blockIO: item.BlockIO || null,
          pids: item.PIDs || null
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

async function listServices() {
  // 1. Lee el archivo compose para obtener la lista de todos los servicios definidos
  let composeConfig;
  try {
    const composeFileContent = await readFile(COMPOSE_FILE, "utf-8");
    composeConfig = yaml.load(composeFileContent);
  } catch (e) {
    console.error(`Error: No se pudo leer o parsear el archivo ${COMPOSE_FILE}.`, e);
    throw new Error(`No se encontró o no se pudo leer el archivo de compose: ${COMPOSE_FILE}`);
  }

  const allServiceNames = Object.keys(composeConfig.services || {});
  if (allServiceNames.length === 0) {
    return []; // No hay servicios definidos en el archivo compose
  }

  // 2. Obtiene el estado actual de los contenedores desde docker
  const ps = await dockerCompose(["ps", "--all", "--format", "json"]);
  const rows = normalizePs(ps.stdout);

  // 3. Itera sobre los servicios del archivo compose y los enriquece con datos en vivo
  return allServiceNames.map((id) => {
    const serviceConfig = composeConfig.services[id];
    const row = rows.find((item) => item.Service === id);
    const meta = getServiceMeta(id, serviceConfig, row) || {};

    const containerName = row?.Name || serviceConfig.container_name || `${path.basename(COMPOSE_DIR)}_${id}_1`;

    return {
      id,
      label: meta.label || serviceConfig.container_name || id,
      container: containerName,
      engine: meta.engine || null,
      client: meta.client || null,
      state: row?.State || "exited",
      status: row?.Status || "Detenido",
      image: row?.Image || serviceConfig.image || "",
      // La salida de `ps` para los puertos es mejor porque muestra el puerto del host
      ports: row?.Publishers || serviceConfig.ports || [],
      defaultScript: meta.defaultScript || `echo "Servicio '${id}' no configurado para ejecución de scripts."`,
      permissionTemplate: meta.permissionTemplate || null
    };
  });
}

function dbExecArgs(service, script) {
  const meta = getServiceMeta(service);
  if (!meta) {
    throw new Error(`No se pudo determinar el motor de base de datos para el servicio '${service}'.`);
  }

  if (meta.engine === "mysql") {
    return ["exec", "-T", service, "mysql", "-uroot", "-proot", "-e", script];
  }
  if (meta.engine === "postgresql") {
    return ["exec", "-T", service, "psql", "-U", "USUARIOPRINCIPAL", "-d", "dbejemplo", "-v", "ON_ERROR_STOP=1", "-c", script];
  }
  if (meta.engine === "mongodb") {
    return ["exec", "-T", service, "mongo", "-u", "USUARIOPRINCIPAL", "-p", "root", "--authenticationDatabase", "admin", "--eval", script];
  }
  if (meta.engine === "cassandra") {
    return ["exec", "-T", service, "cqlsh", "-e", script];
  }
  if (meta.engine === "sqlserver") {
    return ["exec", "-T", service, "sh", "-lc", `if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -Q \"$SQL_SCRIPT\"; else /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P 'Password123!' -Q \"$SQL_SCRIPT\"; fi`];
  }
  throw new Error(`Servicio no soportado: ${service}`);
}

async function handleApiRequest(req, res, pathname, user, permissions) {
  if (req.method === "GET" && pathname === "/api/health") {
    const docker = await run("docker", ["version", "--format", "{{.Server.Version}}"], { timeout: 15000 });
    return sendJson(res, 200, {
      ok: docker.ok,
      composeFile: COMPOSE_FILE,
      composeDir: COMPOSE_DIR,
      dockerVersion: docker.stdout,
      error: docker.stderr,
      user: { id: user.id, services: user.services || [], permissions },
      roles: USERS_DB.roles
    });
  }

  if (req.method === "GET" && pathname === "/api/services") {
    // Todos los usuarios ven todos los servicios. Los permisos se aplican por acción.
    const services = await listServices();
    return sendJson(res, 200, { services });
  }

  if (req.method === "POST" && pathname === "/api/services/add") {
    if (!permissions.allowedCompose.includes("up")) {
      throw new Error("No tienes permiso para crear contenedores.");
    }
    const body = await readJson(req);
    const { id, image, container_name, ports, environment, command, restart } = body;
    if (!id || !image) {
      throw new Error("El nombre del servicio y la imagen son requeridos.");
    }
    const composeFileContent = await readFile(COMPOSE_FILE, "utf-8");
    const composeConfig = yaml.load(composeFileContent) || {};
    composeConfig.services = composeConfig.services || {};

    if (Object.prototype.hasOwnProperty.call(composeConfig.services, id)) {
      throw new Error(`El servicio '${id}' ya existe en el archivo Compose.`);
    }

    const serviceDefinition = { image };
    if (container_name) serviceDefinition.container_name = container_name;
    if (ports) {
      serviceDefinition.ports = Array.isArray(ports) ? ports : String(ports).split("\n").map((line) => line.trim()).filter(Boolean);
    }
    if (environment) {
      const envLines = Array.isArray(environment) ? environment : String(environment).split("\n");
      const envObject = {};
      envLines.forEach((line) => {
        const trimmed = String(line).trim();
        if (!trimmed) return;
        const [key, ...rest] = trimmed.split("=");
        envObject[key.trim()] = rest.join("=").trim();
      });
      serviceDefinition.environment = envObject;
    }
    if (command) serviceDefinition.command = command;
    if (restart) serviceDefinition.restart = restart;

    composeConfig.services[id] = serviceDefinition;
    const newYaml = yaml.dump(composeConfig, { noRefs: true, sortKeys: false });
    await writeFile(COMPOSE_FILE, newYaml, "utf-8");

    const upResult = await dockerCompose(["up", "-d", id], { timeout: 240000 });
    const services = await listServices();
    return sendJson(res, upResult.ok ? 201 : 500, { result: upResult, services });
  }

  if (req.method === "GET" && pathname === "/api/resources") {
    const services = await listServices();
    const containers = services.map((service) => service.container).filter(Boolean);
    const resources = await getContainerResources(containers);
    const resourcesByContainer = Object.fromEntries(resources.map((item) => [item.name, item]));

    return sendJson(res, 200, {
      host: await getHostResources(),
      services: services.map((service) => ({
        ...service,
        resources: resourcesByContainer[service.container] || null
      }))
    });
  }

  if (req.method === "POST" && pathname === "/api/compose") {
    const { action, service } = await readJson(req);
    if (!permissions.allowedCompose.includes(action)) {
      throw new Error(`Acción '${action}' no permitida para tu usuario.`);
    }
    if (service) {
      await validateService(service);
      if (!permissions.canSeeAllServices && !user.services.includes(service)) {
        throw new Error(`No tienes permiso para gestionar el servicio '${service}'.`);
      }
    }
    const args = action === "up"
      ? ["up", "-d", ...(service ? [service] : [])]
      : action === "pull"
        ? ["pull", ...(service ? [service] : [])]
        : [action, ...(service ? [service] : [])];
    const result = await dockerCompose(args, { timeout: 240000 });
    return sendJson(res, result.ok ? 200 : 500, { result, services: await listServices() });
  }

  if (req.method === "GET" && pathname.startsWith("/api/logs/")) {
    if (!permissions.canGetLogs) throw new Error("No tienes permiso para ver logs.");
    const service = decodeURIComponent(pathname.split("/").pop());
    await validateService(service);
    if (!permissions.canSeeAllServices && !user.services.includes(service)) {
      throw new Error(`No tienes permiso para ver los logs de '${service}'.`);
    }
    const result = await dockerCompose(["logs", "--tail", "160", service], { timeout: 30000 });
    return sendJson(res, result.ok ? 200 : 500, { result });
  }

  if (req.method === "POST" && pathname === "/api/query") {
    if (!permissions.canQuery) throw new Error("No tienes permiso para ejecutar consultas.");
    const { service, script } = await readJson(req);
    if (permissions.isSelectOnly) {
      if (!script.trim().toLowerCase().startsWith("select")) {
        throw new Error("Solo se permiten consultas SELECT para tu rol.");
      }
    }
    getServiceMeta(service); // Valida que es un servicio de DB conocido
    if (!script || String(script).trim().length < 2) throw new Error("Escribe una consulta o script primero.");
    const result = service === "sqlserver"
      ? await executeSqlServer(script)
      : await run("docker", dbExecArgs(service, script), { timeout: 120000 });
    return sendJson(res, result.ok ? 200 : 500, { result });
  }

  if (pathname.startsWith("/api/users")) {
    if (!permissions.canManageUsers) {
      throw new Error("No tienes permiso para gestionar usuarios.");
    }

    if (req.method === "GET") {
      // Devolvemos solo los nombres de usuario y sus permisos, no las contraseñas.
      const safeUsers = Object.fromEntries(Object.entries(USERS_DB.users).map(([id, u]) => [id, { permissions: u.permissions, services: u.services }]));
      return sendJson(res, 200, { users: safeUsers });
    }

    if (req.method === "POST") {
      const { userId, password, permissions, services } = await readJson(req);
      if (!userId || !password || !permissions) throw new Error("Usuario, contraseña y permisos son requeridos.");
      if (USERS_DB.users[userId]) throw new Error(`El usuario '${userId}' ya existe.`);

      USERS_DB.users[userId] = { password, permissions, services: services || [] };
      await saveUsersDb();
      // Devolvemos solo los nombres de usuario y sus permisos, no las contraseñas.
      const safeUsers = Object.fromEntries(Object.entries(USERS_DB.users).map(([id, u]) => [id, { permissions: u.permissions, services: u.services }]));
      return sendJson(res, 201, { users: safeUsers });
    }
    
    if (req.method === "PUT" && pathname.startsWith("/api/users/")) {
      const userId = decodeURIComponent(pathname.split("/").pop());
      if (!USERS_DB.users[userId]) throw new Error(`El usuario '${userId}' no existe.`);
      const { password, permissions, services } = await readJson(req);

      if (password) USERS_DB.users[userId].password = password;
      if (permissions) USERS_DB.users[userId].permissions = permissions;
      if (services !== undefined) USERS_DB.users[userId].services = services;

      await saveUsersDb();
      const safeUsers = Object.fromEntries(Object.entries(USERS_DB.users).map(([id, u]) => [id, { permissions: u.permissions, services: u.services }]));
      return sendJson(res, 200, { users: safeUsers });
    }

    if (req.method === "DELETE") {
      const userId = decodeURIComponent(pathname.split("/").pop());
      if (userId === "admin" || userId === "guest") throw new Error("No se pueden eliminar los usuarios por defecto ('admin', 'guest').");
      if (!USERS_DB.users[userId]) throw new Error(`El usuario '${userId}' no existe.`);
      delete USERS_DB.users[userId];
      await saveUsersDb();
      const safeUsers = Object.fromEntries(Object.entries(USERS_DB.users).map(([id, u]) => [id, { permissions: u.permissions, services: u.services }]));
      return sendJson(res, 200, { users: safeUsers });
    }

    throw new Error("Método no soportado para /api/users");
  }

  sendJson(res, 404, { error: "Ruta no encontrada" });
}

async function staticFile(res, pathname) {
  const cleanPath = pathname === "/" ? "/index.html" : pathname;
  const filePath = path.normalize(path.join(publicDir, cleanPath));
  if (!filePath.startsWith(publicDir)) {
    res.writeHead(403);
    return res.end("Forbidden");
  }
  try {
    const body = await readFile(filePath);
    const ext = path.extname(filePath);
    const type = ext === ".css" ? "text/css" : ext === ".js" ? "text/javascript" : "text/html";
    res.writeHead(200, { "content-type": `${type}; charset=utf-8` });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (req.method === "POST" && url.pathname === "/api/login") {
    try {
      const { userId, password } = await readJson(req);
      const user = USERS_DB.users[userId];
      if (user && user.password === password) {
        return sendJson(res, 200, { ok: true, userId });
      }
      return sendJson(res, 401, { error: "Credenciales incorrectas." });
    } catch (error) {
      return sendJson(res, 400, { error: error.message });
    }
  }

  if (req.method === "GET" && url.pathname.startsWith("/api/logs/stream/")) {
    handleLogStream(req, res, url);
    return;
  }

  if (url.pathname.startsWith("/api/")) {
    try {
      const userId = req.headers["x-user-id"];
      const user = USERS_DB.users[userId];
      if (!user) return sendJson(res, 401, { error: "Usuario no autenticado. Proporcione el header X-User-ID (admin, gerente, trabajador, cliente)." });
      user.id = userId;
      const userPermissions = user.permissions;
      if (!userPermissions) return sendJson(res, 403, { error: `Rol de usuario desconocido: ${user.role}` });
      return await handleApiRequest(req, res, url.pathname, user, userPermissions);
    } catch (error) {
      return sendJson(res, 400, { error: error.message });
    }
  }
  return staticFile(res, url.pathname);
});

server.listen(PORT, HOST, async () => {
  await loadUsersDb();
  console.log(`Dashboard listo en http://${HOST}:${PORT}`);
  console.log(`Compose: ${COMPOSE_FILE}`);
});
