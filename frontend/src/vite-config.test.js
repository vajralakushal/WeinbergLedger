import { describe, it, expect } from "vitest";
import config from "../vite.config.js";

// Change set 1: the dev proxy routes /api to the Rails backend (3000),
// which is what lets the frontend use relative /api paths.
describe("vite dev proxy", () => {
  it("routes /api to the Rails backend on port 3000", () => {
    expect(config.server.proxy["/api"]).toBe("http://localhost:3000");
  });
});
