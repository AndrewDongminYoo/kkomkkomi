import { start } from "./app.js";

start({
  doc: document,
  root: document.getElementById("app"),
  location: window.location,
  fetch: window.fetch.bind(window),
});
