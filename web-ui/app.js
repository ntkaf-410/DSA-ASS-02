const ports = {
  customer: 8081,
  restaurant: 8082,
  order: 8083,
  admin: 8087
};

const $ = (selector) => document.querySelector(selector);
const apiHost = () => ($("#api-host").value || "http://localhost").trim().replace(/\/$/, "");
function endpoint(service, path) {
  let host = apiHost();
  if (!/^https?:\/\//i.test(host)) host = `http://${host}`;
  const url = new URL(host);
  url.port = String(ports[service]);
  url.pathname = path;
  url.search = "";
  url.hash = "";
  return url.toString();
}

function notify(message, error = false) {
  const notice = $("#notice");
  notice.textContent = message;
  notice.classList.toggle("error", error);
}

async function request(service, path, options = {}) {
  const response = await fetch(endpoint(service, path), {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options
  });
  const text = await response.text();
  let body = {};
  try { body = text ? JSON.parse(text) : {}; } catch (_) { body = { message: text }; }
  if (!response.ok) throw new Error(body.message || body.error || `Request failed (${response.status})`);
  return body;
}

function formData(form) {
  return Object.fromEntries(new FormData(form).entries());
}

function renderRows(target, rows, empty = "No records found.") {
  const element = $(target);
  if (!Array.isArray(rows) || rows.length === 0) {
    element.innerHTML = `<span class="muted">${empty}</span>`;
    return;
  }
  element.innerHTML = rows.map((row) => {
    const values = Object.entries(row).slice(0, 4).map(([key, value]) =>
      `<span><strong>${key}:</strong> ${typeof value === "object" ? JSON.stringify(value) : value ?? "-"}</span>`);
    return `<div class="result-row">${values.join("")}</div>`;
  }).join("");
}

async function loadHealth() {
  const services = [
    ["Customer", "customer", "/health"], ["Restaurant", "restaurant", "/health"],
    ["Order", "order", "/health"], ["Admin", "admin", "/health"]
  ];
  const results = await Promise.all(services.map(async ([name, service, path]) => {
    try {
      const data = await request(service, path);
      return `<div class="card"><span class="muted">${name} Service</span><strong class="status">UP</strong><small>${data.name || "Healthy"}</small></div>`;
    } catch (error) {
      return `<div class="card"><span class="muted">${name} Service</span><strong class="status">DOWN</strong><small>${error.message}</small></div>`;
    }
  }));
  $("#health-grid").innerHTML = results.join("");
}

document.querySelectorAll(".nav-item").forEach((button) => button.addEventListener("click", () => {
  document.querySelectorAll(".nav-item, .view").forEach((element) => element.classList.remove("active"));
  button.classList.add("active");
  $(`#${button.dataset.view}`).classList.add("active");
}));

$("#save-api").addEventListener("click", () => {
  localStorage.setItem("foodDeliveryApiHost", apiHost());
  notify("API host saved.");
});
$("#api-host").value = localStorage.getItem("foodDeliveryApiHost") || "http://localhost";
$("#refresh-health").addEventListener("click", () => loadHealth().catch((error) => notify(error.message, true)));

$("#register-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    const customer = await request("customer", "/customers", { method: "POST", body: JSON.stringify(formData(event.target)) });
    $("#current-customer").textContent = `Selected customer #${customer.id}: ${customer.fullName}`;
    notify(`Customer #${customer.id} registered.`);
  } catch (error) { notify(error.message, true); }
});

$("#login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    const customer = await request("customer", "/customers/login", { method: "POST", body: JSON.stringify(formData(event.target)) });
    $("#current-customer").textContent = `Selected customer #${customer.id}: ${customer.fullName}`;
    notify(`Welcome, ${customer.fullName}.`);
  } catch (error) { notify(error.message, true); }
});

$("#address-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = formData(event.target);
  const customerId = data.customerId;
  delete data.customerId;
  try {
    await request("customer", `/customers/${customerId}/addresses`, { method: "POST", body: JSON.stringify(data) });
    notify("Delivery address added.");
  } catch (error) { notify(error.message, true); }
});

$("#load-addresses").addEventListener("click", async () => {
  const id = $("#address-customer-id").value;
  if (!id) return notify("Enter a customer ID first.", true);
  try { renderRows("#addresses", await request("customer", `/customers/${id}/addresses`)); }
  catch (error) { notify(error.message, true); }
});

$("#load-restaurants").addEventListener("click", async () => {
  try {
    const restaurants = await request("restaurant", "/restaurants?page=1&pageSize=50");
    $("#restaurant-list").innerHTML = (restaurants || []).map((r) =>
      `<div class="card"><span class="muted">${r.cuisine || "Restaurant"}</span><strong>${r.name}</strong><small>${r.city || ""} · ID ${r.id}</small></div>`).join("");
  } catch (error) { notify(error.message, true); }
});

$("#load-menu").addEventListener("click", async () => {
  const id = $("#menu-restaurant-id").value;
  if (!id) return notify("Enter a restaurant ID first.", true);
  try { renderRows("#menu-list", await request("restaurant", `/restaurants/${id}/menu?available=true`)); }
  catch (error) { notify(error.message, true); }
});

$("#order-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = formData(event.target);
  const body = {
    customerId: Number(data.customerId), restaurantId: Number(data.restaurantId),
    deliveryAddressId: Number(data.deliveryAddressId),
    items: [{ menuItemId: Number(data.menuItemId), quantity: Number(data.quantity) }]
  };
  try {
    const order = await request("order", "/orders", { method: "POST", body: JSON.stringify(body) });
    notify(`Order ${order.orderId} created.`);
  } catch (error) { notify(error.message, true); }
});

$("#load-orders").addEventListener("click", async () => {
  const id = $("#orders-customer-id").value;
  if (!id) return notify("Enter a customer ID first.", true);
  try { renderRows("#order-list", await request("order", `/orders?customerId=${id}&page=1&pageSize=50`)); }
  catch (error) { notify(error.message, true); }
});

$("#load-admin").addEventListener("click", async () => {
  try {
    const summary = await request("admin", "/admin/reports/summary");
    $("#summary").innerHTML = Object.entries(summary).map(([key, value]) =>
      `<div class="card"><span class="muted">${key}</span><strong>${value ?? "-"}</strong></div>`).join("");
    const services = await request("admin", "/admin/services");
    renderRows("#service-list", Array.isArray(services) ? services : Object.entries(services).map(([name, status]) => ({ name, status })));
  } catch (error) { notify(error.message, true); }
});

loadHealth();
