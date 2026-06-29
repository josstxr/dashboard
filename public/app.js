const state = {
  services: [],
  resources: { host: {}, services: [] },
  selectedService: "postgresql",
  user: null,
  allUsers: {},
  roles: {}, // Para plantillas de permisos
  editModeUser: null,
  logStream: null,
  isFollowingLogs: false
};

const $ = (selector) => document.querySelector(selector);

const els = {
  composePath: $("#composePath"),
  runningCount: $("#runningCount"),
  stoppedCount: $("#stoppedCount"),
  serviceCount: $("#serviceCount"),
  serviceGrid: $("#serviceGrid"),
  dbSelect: $("#dbSelect"),
  logSelect: $("#logSelect"),
  scriptBox: $("#scriptBox"),
  queryOutput: $("#queryOutput"),
  logsBox: $("#logsBox"),
  toast: $("#toast"),
  lastCommand: $("#lastCommand"),
  themeToggle: $("#themeToggle"),
  resourceSummary: $("#resourceSummary"),
  userListContainer: $("#userListContainer"),
  createUserForm: $("#createUserForm"),
  newUserId: $("#newUserId"),
  newUserPassword: $("#newUserPassword"),
  newUserRole: $("#newUserRole"),
  userServiceGrid: $("#userServiceGrid"),
  loginOverlay: $("#loginOverlay"),
  loginForm: $("#loginForm"),
  loginUserId: $("#loginUserId"),
  loginPassword: $("#loginPassword"),
  logoutBtn: $("#logoutBtn"),
  guestLoginBtn: $("#guestLoginBtn"),
  togglePassword: $("#togglePassword"),
  permissionGrid: $("#permissionGrid"),
  userFormTitle: $("#userFormTitle"),
  userFormSubmitBtn: $("#userFormSubmitBtn"),
  cancelEditBtn: $("#cancelEditBtn"),
  followLogsBtn: $("#followLogsBtn"),
  addContainerBtn: $("#addContainerBtn"),
  addContainerPanel: $("#addContainerPanel"),
  addContainerForm: $("#addContainerForm"),
  cancelAddContainerBtn: $("#cancelAddContainerBtn"),
  newServiceId: $("#newServiceId"),
  newServiceImage: $("#newServiceImage"),
  newServiceContainer: $("#newServiceContainer"),
  newServicePorts: $("#newServicePorts"),
  newServiceEnv: $("#newServiceEnv"),
  newServiceCommand: $("#newServiceCommand"),
  newServiceRestart: $("#newServiceRestart")
};

function updateThemeButton(theme = document.documentElement.getAttribute("data-theme") || "light") {
  if (!els.themeToggle) return;
  const isDark = theme === "dark";
  els.themeToggle.setAttribute("aria-label", isDark ? "Cambiar a tema claro" : "Cambiar a tema oscuro");
  els.themeToggle.title = isDark ? "Cambiar a tema claro" : "Cambiar a tema oscuro";
}

function applyInitialTheme() {
  const savedTheme = localStorage.getItem("theme");
  const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const theme = savedTheme || (prefersDark ? "dark" : "light");
  document.documentElement.setAttribute("data-theme", theme);
  updateThemeButton(theme);
}

function toggleTheme() {
  const currentTheme = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", currentTheme);
  localStorage.setItem("theme", currentTheme);
  updateThemeButton(currentTheme);
}

function toast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => els.toast.classList.remove("show"), 3200);
}

async function request(path, options = {}) {
  // La petición de login es la única que no necesita autenticación
  if (path === "/api/login") {
    const response = await fetch(path, { headers: { "content-type": "application/json" }, ...options, body: JSON.stringify(options.body) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Falló el inicio de sesión.");
    return data;
  }
  const userId = localStorage.getItem("userId");
  if (!userId) throw new Error("Usuario no identificado. Por favor, recarga la página.");
  const response = await fetch(path, {
    headers: {
      "content-type": "application/json",
      "X-User-ID": userId
    },
    ...options,
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || data.result?.stderr || "La operación falló.");
  return data;
}

function stateClass(service) {
  const value = String(service.state || "unknown").toLowerCase();
  if (value.includes("running")) return "running";
  if (value.includes("exited")) return "exited";
  if (value.includes("created")) return "created";
  return "unknown";
}

function portText(ports) {
  if (!ports || !ports.length) return "Sin puertos publicados";
  if (typeof ports === "string") return ports;
  return ports.map((port) => {
    if (typeof port === "string") return port;
    const published = port.PublishedPort || port.Published || "";
    const target = port.TargetPort || port.Target || "";
    return published && target ? `${published}:${target}` : JSON.stringify(port);
  }).join(", ");
}

function renderResources() {
  const host = state.resources.host || {};
  const memory = host.memory || {};
  const disk = host.disk || {};

  const cards = (state.resources.services || []).map((service) => {
    const resource = service.resources || {};
    return /*html*/`
      <article class="resource-card">
        <div class="resource-title">${service.label}</div>
        <div class="resource-meta">${service.container}</div>
        <div class="resource-stats">
          <span><strong>${resource.cpuPercent || "—"}</strong><small>CPU</small></span>
          <span><strong>${resource.memoryPercent || "—"}</strong><small>RAM</small></span>
          <span><strong>${resource.memoryUsage || "—"}</strong><small>Memoria</small></span>
        </div>
      </article>
    `;
  }).join("");

  els.resourceSummary.innerHTML = /*html*/`
    <article class="resource-card resource-card--host">
      <div class="resource-title">Sistema</div>
      <div class="resource-meta">${host.platform || "Host"} · ${host.cpuCount || 0} CPU</div>
      <div class="resource-stats">
        <span><strong>${memory.percent || 0}%</strong><small>RAM usada</small></span>
        <span><strong>${Math.round((memory.used || 0) / 1024 / 1024 / 1024)} GB</strong><small>RAM usada</small></span>
        <span><strong>${Math.round((disk.used || 0) / 1024 / 1024 / 1024)} GB</strong><small>Disco usado</small></span>
      </div>
    </article>
    ${cards || '<article class="resource-card"><div class="resource-title">Sin datos</div><div class="resource-meta">No se pudieron obtener métricas de Docker.</div></article>'}
  `;
}

function render() {
  const running = state.services.filter((item) => stateClass(item) === "running").length;
  els.runningCount.textContent = running;
  els.stoppedCount.textContent = Math.max(state.services.length - running, 0);
  els.serviceCount.textContent = state.services.length;

  if (state.user) {
    const { permissions } = state.user;
    const allowedGlobal = permissions.allowedCompose || [];
    $("#startAllBtn").style.display = allowedGlobal.includes("up") ? "" : "none";
    $("#stopAllBtn").style.display = allowedGlobal.includes("stop") ? "" : "none";
    $("#restartAllBtn").style.display = allowedGlobal.includes("restart") ? "" : "none";
    $("#nav-data").style.display = permissions.canQuery ? "" : "none";
    $("#nav-admin").style.display = permissions.canManageUsers ? "" : "none";
    $("#nav-logs").style.display = permissions.canGetLogs ? "" : "none";
    $("#permissionTemplateBtn").style.display = permissions.canUsePermissionScripts ? "" : "none";
    els.addContainerBtn.style.display = allowedGlobal.includes("up") ? "" : "none";
  }

  els.serviceGrid.innerHTML = state.services.map((service) => {
    const { permissions, services: userServices = [] } = state.user;
    const canActOnService = permissions.canSeeAllServices || userServices.includes(service.id);

    const allowedActions = permissions.allowedCompose || [];

    const upButton = allowedActions.includes("up") && canActOnService ? /*html*/`
      <button data-action="up" data-service="${service.id}" title="Levantar">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
        <span>Levantar</span>
      </button>` : "";
    const restartButton = allowedActions.includes("restart") && canActOnService ? /*html*/`
      <button data-action="restart" data-service="${service.id}" title="Reiniciar">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"></polyline><polyline points="1 20 1 14 7 14"></polyline><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path></svg>
        <span>Reiniciar</span>
      </button>` : "";
    const stopButton = allowedActions.includes("stop") && canActOnService ? /*html*/`
      <button data-action="stop" data-service="${service.id}" title="Detener">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12"></rect></svg>
        <span>Detener</span>
      </button>` : "";

    const terminalButton = permissions.canGetLogs && canActOnService ? /*html*/`
      <button data-action="logs" data-service="${service.id}" title="Abrir terminal">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"></polyline><line x1="12" y1="19" x2="20" y2="19"></line></svg>
        <span>Terminal</span>
      </button>` : "";

    return /*html*/`
      <article class="card">
        <div class="card-head">
          <div>
            <h3>${service.label}</h3>
            <small>${service.container}</small>
          </div>
          <span class="status ${stateClass(service)}">${service.state.toLowerCase()}</span>
        </div>
        <div class="meta">
          <span>${service.status}</span>
          <span>${portText(service.ports)}</span>
        </div>
        <div class="card-actions">
          ${terminalButton}
          ${upButton}
          ${restartButton}
          ${stopButton}
        </div>
      </article>
    `;
  }).join("");

  const options = state.services.map((service) => `<option value="${service.id}">${service.label}</option>`).join("");
  els.dbSelect.innerHTML = options;
  els.logSelect.innerHTML = options;
  els.dbSelect.value = state.selectedService;
  els.logSelect.value = state.selectedService;
}

async function refresh() {
  const health = await request("/api/health");
  state.user = health.user;
  state.roles = health.roles;
  els.composePath.textContent = `${health.ok ? "Docker conectado" : "Docker no disponible"} · ${health.composeFile}`;
  const data = await request("/api/services");
  state.services = data.services;
  const resources = await request("/api/resources").catch(() => ({ host: {}, services: [] }));
  state.resources = resources;
  if (!state.services.some((service) => service.id === state.selectedService)) {
    state.selectedService = state.services[0]?.id || "postgresql";
  }
  renderResources();
  render();
  if (!els.scriptBox.value.trim()) fillInsertTemplate();
  if (els.addContainerPanel) {
    els.addContainerPanel.style.display = "none";
  }
}

async function compose(action, service) {
  toast(`${action}${service ? `: ${service}` : ": todos"}...`);
  const data = await request("/api/compose", { method: "POST", body: { action, service } });
  state.services = data.services;
  render();
  const stderr = data.result.stderr ? `\n${data.result.stderr}` : "";
  toast(data.result.ok ? "Operación completada" : "Revisa el resultado");
  return `${data.result.stdout}${stderr}`.trim();
}

function selectedMeta() {
  return state.services.find((service) => service.id === state.selectedService);
}

function fillInsertTemplate() {
  const meta = selectedMeta();
  els.scriptBox.value = meta?.defaultScript || "";
}

function fillPermissionTemplate() {
  const meta = selectedMeta();
  els.scriptBox.value = meta?.permissionTemplate || "";
}

async function runScript() {
  const service = state.selectedService;
  const script = els.scriptBox.value;
  els.queryOutput.textContent = "Ejecutando...";
  const data = await request("/api/query", { method: "POST", body: { service, script } });
  els.lastCommand.textContent = data.result.command;
  els.queryOutput.textContent = [data.result.stdout, data.result.stderr].filter(Boolean).join("\n") || "Comando ejecutado sin salida.";
  toast(data.result.ok ? "Script ejecutado" : "El script terminó con error");
}

async function loadLogs() {
  if (state.isFollowingLogs) return;
  const service = state.selectedService;
  els.logsBox.textContent = "Cargando registros...";
  const data = await request(`/api/logs/${encodeURIComponent(service)}`);
  els.logsBox.textContent = [data.result.stdout, data.result.stderr].filter(Boolean).join("\n") || "Sin registros recientes.";
}

function toggleLogFollowing() {
  if (state.isFollowingLogs) {
    if (state.logStream) {
      state.logStream.close();
      state.logStream = null;
    }
    state.isFollowingLogs = false;
    els.followLogsBtn.classList.remove("active");
    els.followLogsBtn.textContent = "Seguir";
    els.logsBox.textContent += "\n\n--- Dejaste de seguir los registros ---";
  } else {
    state.isFollowingLogs = true;
    els.followLogsBtn.classList.add("active");
    els.followLogsBtn.textContent = "Siguiendo...";
    els.logsBox.textContent = "Conectando al stream de registros...\n";
    const service = state.selectedService;
    state.logStream = new EventSource(`/api/logs/stream/${encodeURIComponent(service)}`);
    state.logStream.onmessage = (event) => {
      els.logsBox.textContent += event.data + "\n";
      els.logsBox.scrollTop = els.logsBox.scrollHeight;
    };
    state.logStream.onerror = () => {
      els.logsBox.textContent += "\n--- Se perdió la conexión con el servidor ---";
      if (state.isFollowingLogs) toggleLogFollowing();
    };
  }
}

async function loadUsers() {
  try {
    const data = await request("/api/users");
    state.allUsers = data.users;
    renderUserList();
  } catch (error) {
    els.userListContainer.innerHTML = `<p class="error">${error.message}</p>`;
  }
}

function renderUserList() {
  const userRows = Object.entries(state.allUsers).map(([userId, user]) => /*html*/`
    <tr>
      <td>${userId}</td>
      <td>${getRoleFromPermissions(user.permissions)}</td>
      <td>${user.permissions.canSeeAllServices ? 'Todos' : (user.services?.join(", ") || "-")}</td>
      <td><div class="actions">
        ${(userId !== "admin" && userId !== "guest") ? `
          <button class="ghost" data-edit-user="${userId}">Editar</button>
          <button class="danger" data-delete-user="${userId}">Eliminar</button>
        ` : ""}
      </div></td>
    </tr>
  `).join("");

  els.userListContainer.innerHTML = /*html*/`
    <table class="user-table">
      <thead>
        <tr>
          <th>Usuario</th>
          <th>Rol</th>
          <th>Servicios</th>
          <th>Acción</th>
        </tr>
      </thead>
      <tbody>${userRows}</tbody>
    </table>
  `;

  renderPermissionEditor();
  renderServiceSelector();
}

function renderServiceSelector() {
  if (!state.services) return;
  els.userServiceGrid.innerHTML = state.services.map(service => /*html*/`
      <label class="permission-item">
          <input type="checkbox" name="service" value="${service.id}">
          ${service.label}
      </label>
  `).join("");
}

function getRoleFromPermissions(permissions) {
  for (const roleName in state.roles) {
    if (JSON.stringify(state.roles[roleName]) === JSON.stringify(permissions)) {
      return roleName;
    }
  }
  return "personalizado";
}

function renderPermissionEditor() {
  // Defensive check: ensure roles and the admin template exist before proceeding.
  if (!state.roles || !state.roles.administrador) {
    els.permissionGrid.innerHTML = `<p class="error">No se pudieron cargar las plantillas de permisos.</p>`;
    els.newUserRole.innerHTML = `<option value="">Error</option>`;
    return;
  }

  const roleOptions = `<option value="">-- Seleccionar plantilla --</option>` +
    Object.keys(state.roles).map(role => `<option value="${role}">${role}</option>`).join("");
  els.newUserRole.innerHTML = roleOptions;

  const allPossibleBooleanPerms = new Set();
  Object.values(state.roles).forEach(role => {
    Object.entries(role).forEach(([key, value]) => {
      if (typeof value === 'boolean') allPossibleBooleanPerms.add(key);
    });
  });
  const booleanPermissions = [...allPossibleBooleanPerms];

  els.permissionGrid.innerHTML = booleanPermissions.map(perm => /*html*/`
    <label class="permission-item">
      <input type="checkbox" name="${perm}" id="perm-${perm}">
      ${perm.replace(/([A-Z])/g, ' $1').toLowerCase()}
    </label>
  `).join("") + /*html*/`
    <label class="permission-item" style="grid-column: 1 / -1;">
      <span>Allowed Compose:</span>
      <input type="text" name="allowedCompose" id="perm-allowedCompose" style="flex-grow: 1; margin-left: 8px;" placeholder="up,stop,restart...">
    </label>
  `;
}

async function deleteUser(userId) {
  await request(`/api/users/${encodeURIComponent(userId)}`, { method: "DELETE" });
  toast(`Usuario '${userId}' eliminado.`);
  await loadUsers();
}

function enterEditMode(userId) {
  const userToEdit = state.allUsers[userId];
  if (!userToEdit) return;

  state.editModeUser = userId;
  els.userFormTitle.textContent = `Editando a '${userId}'`;
  els.userFormSubmitBtn.textContent = "Actualizar Usuario";
  els.cancelEditBtn.style.display = "inline-flex";

  els.newUserId.value = userId;
  els.newUserId.disabled = true;
  els.newUserPassword.placeholder = "(Dejar en blanco para no cambiar)";

  // Limpiar y rellenar checkboxes de servicios
  els.createUserForm.querySelectorAll('input[name="service"]').forEach(cb => cb.checked = false);
  if (userToEdit.services) {
    userToEdit.services.forEach(serviceId => {
      const checkbox = els.createUserForm.querySelector(`input[name="service"][value="${serviceId}"]`);
      if (checkbox) checkbox.checked = true;
    });
  }

  // Rellenar permisos
  const { permissions } = userToEdit;
  Object.keys(permissions).forEach(permKey => {
    const el = $(`#perm-${permKey}`);
    if (el?.type === "checkbox") {
      el.checked = permissions[permKey];
    }
  });
  $(`#perm-allowedCompose`).value = (permissions.allowedCompose || []).join(",");

  els.newUserRole.value = getRoleFromPermissions(permissions);
}

document.addEventListener("click", async (event) => {
  const actionButton = event.target.closest("[data-action]");
  if (actionButton) {
    const { action, service } = actionButton.dataset;
    const composeActions = ["up", "stop", "restart", "down", "pull"];

    if (composeActions.includes(action)) {
      try {
        await compose(action, service);
      } catch (error) {
        toast(error.message);
      }
    } else if (action === 'logs') {
        state.selectedService = service;
        els.logSelect.value = service;
        els.dbSelect.value = service;

        // Switch view programmatically
        document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
        document.querySelectorAll(".view").forEach((item) => item.classList.remove("active"));
        $('#nav-logs').classList.add("active");
        $('#logsView').classList.add("active");

        // Stop any other following and start the new one
        if (state.isFollowingLogs) toggleLogFollowing(); // stop
        setTimeout(() => {
            if (!state.isFollowingLogs) toggleLogFollowing(); // start
        }, 50);
    }
  }
  const deleteButton = event.target.closest("[data-delete-user]");
  if (deleteButton) {
    const userId = deleteButton.dataset.deleteUser;
    if (confirm(`¿Estás seguro de que quieres eliminar al usuario '${userId}'?`)) {
      try {
        await deleteUser(userId);
      } catch (error) { toast(error.message); }
    }
  }
  const editButton = event.target.closest("[data-edit-user]");
  if (editButton) {
    const userId = editButton.dataset.editUser;
    enterEditMode(userId);
  }
});

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    document.querySelectorAll(".view").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    $(`#${button.dataset.view}View`).classList.add("active");
    if (button.dataset.view === "logs" && state.user.permissions.canGetLogs) {
      loadLogs().catch((error) => toast(error.message));
    }
    if (button.dataset.view !== "logs" && state.isFollowingLogs) toggleLogFollowing();
    if (button.dataset.view === "admin") loadUsers().catch((error) => toast(error.message));
  });
});

$("#refreshBtn").addEventListener("click", () => refresh().catch((error) => toast(error.message)));
$("#startAllBtn").addEventListener("click", () => compose("up").catch((error) => toast(error.message)));
$("#stopAllBtn").addEventListener("click", () => compose("stop").catch((error) => toast(error.message)));
$("#restartAllBtn").addEventListener("click", () => compose("restart").catch((error) => toast(error.message)));
els.themeToggle.addEventListener("click", toggleTheme);
$("#insertTemplateBtn").addEventListener("click", fillInsertTemplate);
$("#permissionTemplateBtn").addEventListener("click", fillPermissionTemplate);
$("#runScriptBtn").addEventListener("click", () => runScript().catch((error) => {
  els.queryOutput.textContent = error.message;
  toast(error.message);
}));

els.dbSelect.addEventListener("change", () => {
  state.selectedService = els.dbSelect.value;
  fillInsertTemplate();
});

els.logSelect.addEventListener("change", () => {
  state.selectedService = els.logSelect.value;
  els.dbSelect.value = state.selectedService;
  if (state.isFollowingLogs) {
    toggleLogFollowing(); // Stop old stream
  }
  if (state.user.permissions.canGetLogs) {
    loadLogs().catch((error) => toast(error.message));
  }
});

els.createUserForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const userId = els.newUserId.value.trim();
  const password = els.newUserPassword.value;
  const services = [...els.createUserForm.querySelectorAll('input[name="service"]:checked')].map(cb => cb.value);

  const permissions = {};
  const formElements = event.target.elements;
  for (const el of formElements) {
    if (el.type === "checkbox" && el.name !== "service") {
      permissions[el.name] = el.checked;
    } else if (el.name === "allowedCompose") {
      permissions.allowedCompose = el.value.split(",").map(s => s.trim()).filter(Boolean);
    }
  }

  const body = { permissions, services };

  try {
    if (state.editModeUser) {
      if (password) {
        body.password = password;
      }
      await request(`/api/users/${encodeURIComponent(state.editModeUser)}`, { method: "PUT", body });
      toast(`Usuario '${state.editModeUser}' actualizado.`);
    } else {
      body.userId = userId;
      body.password = password;
      if (!body.password) {
        toast("La contraseña es requerida para nuevos usuarios.");
        return;
      }
      await request("/api/users", { method: "POST", body });
      toast(`Usuario '${userId}' creado.`);
    }
    els.createUserForm.reset();
    cancelEditMode();
    await loadUsers();
  } catch (error) {
    toast(error.message);
  }
});

els.logoutBtn.addEventListener("click", () => {
  localStorage.removeItem("userId");
  window.location.reload();
});

function toggleAddContainerPanel(show) {
  if (!els.addContainerPanel) return;
  els.addContainerPanel.style.display = show ? "block" : "none";
}

if (els.addContainerBtn) {
  els.addContainerBtn.addEventListener("click", () => {
    toggleAddContainerPanel(true);
  });
}

if (els.cancelAddContainerBtn) {
  els.cancelAddContainerBtn.addEventListener("click", () => {
    toggleAddContainerPanel(false);
  });
}

if (els.addContainerForm) {
  els.addContainerForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const payload = {
      id: els.newServiceId.value.trim(),
      image: els.newServiceImage.value.trim(),
      container_name: els.newServiceContainer.value.trim() || undefined,
      ports: els.newServicePorts.value.trim(),
      environment: els.newServiceEnv.value.trim(),
      command: els.newServiceCommand.value.trim() || undefined,
      restart: els.newServiceRestart.value.trim() || undefined
    };

    try {
      const data = await request("/api/services/add", { method: "POST", body: payload });
      state.services = data.services;
      render();
      toggleAddContainerPanel(false);
      els.addContainerForm.reset();
      toast("Contenedor agregado y levantado correctamente.");
    } catch (error) {
      toast(error.message);
    }
  });
}

function cancelEditMode() {
  state.editModeUser = null;
  els.userFormTitle.textContent = "Crear nuevo usuario";
  els.userFormSubmitBtn.textContent = "Crear Usuario";
  els.cancelEditBtn.style.display = "none";
  els.newUserId.disabled = false;
  els.newUserPassword.placeholder = "Contraseña";
  els.createUserForm.reset();
}

els.newUserRole.addEventListener("change", () => {
  // This listener is now outside renderPermissionEditor to avoid being re-added.
  if (!state.roles || !state.roles.administrador) return;

  const selectedRole = els.newUserRole.value;
  const template = state.roles[selectedRole] || {};

  const allPossibleBooleanPerms = new Set();
  Object.values(state.roles).forEach(role => {
    Object.entries(role).forEach(([key, value]) => {
      if (typeof value === 'boolean') allPossibleBooleanPerms.add(key);
    });
  });
  const booleanPermissions = [...allPossibleBooleanPerms];

  booleanPermissions.forEach(perm => {
    const checkbox = $(`#perm-${perm}`);
    if (checkbox) checkbox.checked = template[perm] || false;
  });
  const composeInput = $(`#perm-allowedCompose`);
  if (composeInput) composeInput.value = (template.allowedCompose || []).join(",");
});

els.cancelEditBtn.addEventListener("click", cancelEditMode);

els.followLogsBtn.addEventListener("click", toggleLogFollowing);

els.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const userId = els.loginUserId.value.trim();
  const password = els.loginPassword.value;
  if (!userId || !password) return toast("Usuario y contraseña son requeridos.");
  try {
    await request("/api/login", { method: "POST", body: { userId, password } });
    localStorage.setItem("userId", userId);
    els.loginOverlay.classList.add("hidden");
    startApp();
  } catch (error) {
    toast(error.message);
  }
});

els.guestLoginBtn.addEventListener("click", async () => {
  try {
    // Intenta iniciar sesión con las credenciales de invitado predefinidas
    await request("/api/login", { method: "POST", body: { userId: "guest", password: "guest" } });
    localStorage.setItem("userId", "guest");
    els.loginOverlay.classList.add("hidden");
    startApp();
  } catch (error) {
    toast(`Error de invitado: ${error.message}`);
  }
});

els.togglePassword.addEventListener("click", () => {
  const isPassword = els.loginPassword.type === "password";
  els.loginPassword.type = isPassword ? "text" : "password";
  const eyeIcon = els.togglePassword.querySelector(".icon-eye");
  const eyeOffIcon = els.togglePassword.querySelector(".icon-eye-off");
  eyeIcon.style.display = isPassword ? "none" : "block";
  eyeOffIcon.style.display = isPassword ? "block" : "none";
});

function handleLogin() {
  let userId = localStorage.getItem("userId");
  if (userId) {
    els.loginOverlay.classList.add("hidden");
    return userId;
  } else {
    els.loginOverlay.classList.remove("hidden");
    return null;
  }
}

function startApp() {
  refresh().catch((error) => {
    const errorMessage = `Error de conexión: ${error.message}`;
    els.composePath.textContent = errorMessage;
    toast(error.message);
    // Si la autenticación falla (ej. usuario no válido), se borra y se muestra el login.
    if (error.message.includes("Usuario no autenticado") || error.message.includes("Credenciales incorrectas")) {
      localStorage.removeItem("userId");
      handleLogin();
    }
  });
}

applyInitialTheme();
const userId = handleLogin();
if (userId) {
  startApp();
}
