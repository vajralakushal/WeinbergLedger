import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, afterEach } from "vitest";
import UsersDashboard from "./UsersDashboard";

const noop = () => {};

const USERS = [
  { user_id: 1234, first_name: "Ada", last_name: "Lovelace", username: "ada", approval_status: "PENDING", admin_status: false },
  { user_id: 5678, first_name: "Grace", last_name: "Hopper", username: "grace", approval_status: "APPROVED", admin_status: true },
];

afterEach(() => {
  vi.restoreAllMocks();
});

// Routes by [urlSubstring, response] pairs, always attaching a spy call log.
function mockFetch(handlers, spy = vi.fn()) {
  const fn = vi.fn((url, opts) => {
    spy(url, opts);
    for (const [pattern, resp] of handlers) {
      if (String(url).includes(pattern)) {
        return Promise.resolve({ ok: resp.ok ?? true, json: () => Promise.resolve(resp.body) });
      }
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
  fn.spy = spy;
  return fn;
}

describe("UsersDashboard", () => {
  it("loads and lists users with the bearer token", async () => {
    const fetchMock = mockFetch([["/api/admin/users", { body: USERS }]]);
    global.fetch = fetchMock;

    render(<UsersDashboard onBack={noop} authToken="tok-123" />);

    expect(await screen.findByText("ada")).toBeInTheDocument();
    expect(screen.getByText("grace")).toBeInTheDocument();
    const [url, opts] = fetchMock.spy.mock.calls[0];
    expect(url).toBe("/api/admin/users");
    expect(opts.headers.Authorization).toBe("Bearer tok-123");
  });

  it("only shows Approve/Deny for pending users", async () => {
    global.fetch = mockFetch([["/api/admin/users", { body: USERS }]]);
    render(<UsersDashboard onBack={noop} authToken="tok" />);
    await screen.findByText("ada");

    const rows = screen.getAllByRole("row");
    const adaRow = rows.find((r) => r.textContent.includes("ada"));
    const graceRow = rows.find((r) => r.textContent.includes("grace"));
    expect(adaRow.textContent).toMatch(/Approve/);
    expect(graceRow.textContent).not.toMatch(/Approve/);
  });

  it("approving a user re-fetches the list", async () => {
    const fetchMock = mockFetch([
      ["/approve", { body: { ok: true } }],
      ["/api/admin/users", { body: USERS }],
    ]);
    global.fetch = fetchMock;

    render(<UsersDashboard onBack={noop} authToken="tok" />);
    await screen.findByText("ada");

    await userEvent.click(screen.getAllByRole("button", { name: "Approve" })[0]);

    await waitFor(() => {
      const approveCall = fetchMock.spy.mock.calls.find(([url]) => String(url).includes("/approve"));
      expect(approveCall).toBeTruthy();
      expect(approveCall[0]).toBe("/api/admin/users/1234/approve");
    });
  });

  it("reset password shows the one-time temporary password", async () => {
    global.fetch = mockFetch([
      ["/reset_password", { body: { ok: true, temp_password: "xY7z9Qa2" } }],
      ["/api/admin/users", { body: USERS }],
    ]);
    render(<UsersDashboard onBack={noop} authToken="tok" />);
    await screen.findByText("ada");

    await userEvent.click(screen.getAllByRole("button", { name: "Reset password" })[0]);
    expect(await screen.findByText("xY7z9Qa2")).toBeInTheDocument();
  });
});
