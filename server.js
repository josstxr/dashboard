import express from 'express';
import cors from 'cors';
import Docker from 'dockerode';
import path from 'path';
import { fileURLToPath } from 'url';
import { exec } from 'child_process';
import { promisify } from 'util';
import { readFile } from 'fs/promises';
import yaml from 'js-yaml';

// --- Configuración ---
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Asumimos que este archivo está en la raíz del proyecto. Ver nota sobre la ubicación del archivo.
const projectRoot = __dirname; 
const composeFilePath = path.join(projectRoot, 'docker-compose.yml');

const app = express();
const port = 3000;
const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const execPromise = promisify(exec);

// --- Middlewares ---
app.use(cors());
app.use(express.json()); // Para parsear el cuerpo de las peticiones POST
app.use(express.static(path.join(projectRoot, 'public')));

// --- Funciones Auxiliares ---

/**
 * Ejecuta un comando de shell en el directorio del proyecto.
 * @param {string} command El comando a ejecutar.
 * @returns {Promise<{stdout: string, stderr: string, ok: boolean}>}
 */
async function runCommand(command) {
  // El flag -f especifica la ruta del archivo compose, haciendo el comando más robusto.
  const fullCommand = `docker-compose -f "${composeFilePath}" ${command}`;
  console.log(`Ejecutando: ${fullCommand}`);
  try {
    const { stdout, stderr } = await execPromise(fullCommand, { cwd: projectRoot });
    return { stdout, stderr, ok: true };
  } catch (error) {
    console.error(`Error ejecutando el comando: ${fullCommand}`, error);
    return { stdout: '', stderr: error.message, ok: false };
  }
}

/**
 * Obtiene el estado de todos los servicios definidos en el archivo docker-compose.
 */
async function getServicesState() {
  let composeConfig;
  try {
    const composeFileContent = await readFile(composeFilePath, 'utf-8');
    composeConfig = yaml.load(composeFileContent);
  } catch (e) {
    console.error(`Error: No se pudo leer o parsear el archivo ${composeFilePath}.`);
    throw new Error(`No se encontró o no se pudo leer el archivo docker-compose.yml en la raíz del proyecto.`);
  }

  const { stdout: psOutput, ok: psOk } = await runCommand('ps --format json');
  const runningServices = psOk && psOutput.trim() ? psOutput.trim().split('\n').map(line => JSON.parse(line)) : [];

  const allServiceNames = Object.keys(composeConfig.services || {});

  const services = allServiceNames.map(serviceName => {
    const serviceConfig = composeConfig.services[serviceName];
    const runningInfo = runningServices.find(s => s.Service === serviceName);

    if (runningInfo) {
      return {
        id: serviceName,
        label: serviceConfig.container_name || serviceName,
        container: runningInfo.Name,
        state: runningInfo.State,
        status: runningInfo.Status,
        ports: runningInfo.Publishers?.map(p => ({ PublishedPort: p.PublishedPort, TargetPort: p.TargetPort })) || [],
      };
    } else {
      return {
        id: serviceName,
        label: serviceConfig.container_name || serviceName,
        container: serviceConfig.container_name || `${path.basename(projectRoot)}_${serviceName}_1`,
        state: 'exited',
        status: 'Exited',
        ports: serviceConfig.ports || [],
      };
    }
  });

  return services;
}

// --- API Endpoints ---

app.get('/api/health', async (req, res) => {
  try {
    await docker.ping();
    res.json({ ok: true, composeFile: composeFilePath });
  } catch (error) {
    res.status(500).json({ ok: false, composeFile: composeFilePath, error: 'El demonio de Docker no está corriendo.' });
  }
});

app.get('/api/services', async (req, res) => {
  try {
    const services = await getServicesState();
    res.json({ services });
  } catch (error) {
    res.status(500).json({ error: 'Falló al obtener el estado de los servicios.', details: error.message });
  }
});

app.post('/api/compose', async (req, res) => {
  const { action, service } = req.body;
  if (!action) return res.status(400).json({ error: 'La acción es requerida.' });

  let command = action;
  if (action === 'up') command += ' -d'; // Siempre levantar en modo detached
  if (service) command += ` ${service}`;

  try {
    const result = await runCommand(command);
    const services = await getServicesState(); // Obtener estado actualizado
    res.json({ result, services });
  } catch (error) {
    res.status(500).json({ error: `Falló al ejecutar la acción: ${action}`, details: error.message });
  }
});

app.get('/api/logs/:service', async (req, res) => {
  const { service } = req.params;
  if (!service) return res.status(400).json({ error: 'El nombre del servicio es requerido.' });
  try {
    const result = await runCommand(`logs --tail="100" ${service}`);
    res.json({ result });
  } catch (error) {
    res.status(500).json({ error: `Falló al obtener los logs para ${service}`, details: error.message });
  }
});

app.post('/api/query', async (req, res) => {
  const { service, script } = req.body;
  if (!service || !script) return res.status(400).json({ error: 'El servicio y el script son requeridos.' });
  try {
    const command = `exec -T ${service} sh -c "${script.replace(/"/g, '\\"')}"`;
    const result = await runCommand(command);
    res.json({ result });
  } catch (error) {
    res.status(500).json({ error: `Falló al ejecutar el script en ${service}`, details: error.message });
  }
});

// --- Iniciar el Servidor ---
app.listen(port, () => {
  console.log(`Servidor backend escuchando en http://localhost:${port}`);
  console.log(`Dashboard disponible en http://localhost:3000`);
  console.log(`Esperando el archivo docker-compose en: ${composeFilePath}`);
});