// Runs Zola off the main thread. Messages in: { id, files, options }; out: { id, result } or { id, error }.
// scripts/serve-demo.sh stages zola.js (the library) and zola.wasm next to this file.
import { loadZola } from "./zola.js";

const zola = loadZola(new URL("zola.wasm", import.meta.url));

self.onmessage = async ({ data: { id, files, options } }) => {
  try {
    const result = await (await zola).build({ files, ...options });
    // Transfer the output buffers instead of copying them
    const buffers = new Set([...result.files.values()].map((bytes) => bytes.buffer));
    self.postMessage({ id, result }, [...buffers]);
  } catch (error) {
    self.postMessage({ id, error: String(error?.stack ?? error) });
  }
};
