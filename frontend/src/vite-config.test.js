import { describe, it, expect } from "vitest";
import config from "../vite.config.js";

// Change set 1: the dev proxy routes /api to the Sinatra backend (4567),
// which is what lets the frontend use relative /api paths.
describe("vite dev proxy", () => {
  it("routes /api to the Sinatra backend on port 4567", () => {
    expect(config.server.proxy["/api"]).toBe("http://localhost:4567");
  });
});
