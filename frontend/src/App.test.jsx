import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, beforeEach, vi } from "vitest";
import App from "./App";

// Route mocked fetches by a substring of the URL.
function mockFetch(handlers) {
  return vi.fn((url) => {
    for (const [pattern, resp] of handlers) {
      if (String(url).includes(pattern)) {
        return Promise.resolve({
          ok: resp.ok ?? true,
          status: resp.status ?? 200,
          json: () => Promise.resolve(resp.body),
          blob: () => Promise.resolve(new Blob()),
        });
      }
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
}

beforeEach(() => {
  localStorage.clear();
});

describe("App", () => {
  it("shows the caller IP in the footer (from /api/whoami)", async () => {
    global.fetch = mockFetch([["whoami", { body: { ip: "10.0.0.5" } }]]);
    render(<App />);
    expect(await screen.findByText(/10\.0\.0\.5/)).toBeInTheDocument();
  });

  it("navigates to the audit log page and back", async () => {
    global.fetch = mockFetch([
      ["whoami", { body: { ip: "1.2.3.4" } }],
      ["audit", { body: [] }],
    ]);
    render(<App />);
    await screen.findByText(/1\.2\.3\.4/);

    await userEvent.click(screen.getByText(/View audit log/));
    expect(
      await screen.findByRole("heading", { name: "Audit Log" })
    ).toBeInTheDocument();

    await userEvent.click(screen.getByText(/Back to search/));
    expect(
      await screen.findByRole("heading", { name: "Weinberg Theory Group Library Search" })
    ).toBeInTheDocument();
  });

  it("searches via a relative /api path (not a hardcoded host)", async () => {
    const fetchMock = mockFetch([
      ["whoami", { body: { ip: "1.1.1.1" } }],
      ["search", { body: [] }],
    ]);
    global.fetch = fetchMock;
    render(<App />);

    await userEvent.type(screen.getByPlaceholderText("Search params"), "griffiths{Enter}");

    await waitFor(() => {
      const call = fetchMock.mock.calls.find((c) => String(c[0]).includes("/api/search"));
      expect(call).toBeTruthy();
      expect(String(call[0])).toContain("/api/search?q=griffiths");
      expect(String(call[0]).startsWith("/api/")).toBe(true); // relative, proxied
    });
  });

  it("clicking the title returns to a fresh home (clears results + query)", async () => {
    global.fetch = mockFetch([
      ["whoami", { body: { ip: "1.1.1.1" } }],
      ["search", { body: [{ ID: 1, TITLE: "QM", OWNER: "Alex" }] }],
    ]);
    render(<App />);

    const input = screen.getByPlaceholderText("Search params");
    await userEvent.type(input, "qm{Enter}");
    expect(await screen.findByText("QM")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("heading", { name: "Weinberg Theory Group Library Search" }));

    await waitFor(() => expect(screen.queryByText("QM")).toBeNull());
    expect(screen.getByPlaceholderText("Search params")).toHaveValue("");
  });
});
