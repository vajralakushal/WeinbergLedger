import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, afterEach } from "vitest";
import ChangePasswordModal from "./ChangePasswordModal";

const noop = () => {};

afterEach(() => {
  vi.restoreAllMocks();
});

async function fill(current, next, confirm) {
  await userEvent.type(screen.getByLabelText(/Current password/), current);
  await userEvent.type(screen.getByLabelText(/^New password/), next);
  await userEvent.type(screen.getByLabelText(/Confirm new password/), confirm);
}

describe("ChangePasswordModal", () => {
  it("rejects mismatched new passwords without calling the API", async () => {
    const spy = vi.fn();
    global.fetch = spy;
    render(<ChangePasswordModal onClose={noop} authToken="tok" />);
    await fill("oldpass", "newpass123", "different123");
    await userEvent.click(screen.getByRole("button", { name: "Change Password" }));

    expect(await screen.findByText("New passwords do not match.")).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it("sends the bearer token and shows the server's error on failure", async () => {
    const spy = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      spy(url, opts);
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: false, error: "Current password is incorrect." }) });
    });

    render(<ChangePasswordModal onClose={noop} authToken="tok-123" />);
    await fill("wrongold", "newpass123", "newpass123");
    await userEvent.click(screen.getByRole("button", { name: "Change Password" }));

    expect(await screen.findByText("Current password is incorrect.")).toBeInTheDocument();
    const [url, opts] = spy.mock.calls[0];
    expect(url).toBe("/api/me/password");
    expect(opts.headers.Authorization).toBe("Bearer tok-123");
    expect(JSON.parse(opts.body)).toEqual({
      old_password: "wrongold", new_password: "newpass123", new_password_confirmation: "newpass123",
    });
  });

  it("shows a success message when the change succeeds", async () => {
    global.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: true }) }));
    render(<ChangePasswordModal onClose={noop} authToken="tok" />);
    await fill("oldpass", "newpass123", "newpass123");
    await userEvent.click(screen.getByRole("button", { name: "Change Password" }));

    await waitFor(() => expect(screen.getByText(/password has been changed/)).toBeInTheDocument());
  });
});
