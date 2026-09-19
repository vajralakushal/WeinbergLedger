import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, afterEach } from "vitest";
import LoginModal from "./LoginModal";

const noop = () => {};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("LoginModal", () => {
  it("posts credentials and calls onLogin on success", async () => {
    const spy = vi.fn();
    const onLogin = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      spy(url, opts);
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ ok: true, token: "tok-1", user: { username: "ada" } }),
      });
    });

    render(<LoginModal onClose={noop} onLogin={onLogin} onSignupClick={noop} />);
    await userEvent.type(screen.getByLabelText(/Username/), "ada");
    await userEvent.type(screen.getByLabelText(/Password/), "s3cret");
    await userEvent.click(screen.getByRole("button", { name: "Log In" }));

    await waitFor(() => expect(onLogin).toHaveBeenCalledWith("tok-1", { username: "ada" }));
    const [url, opts] = spy.mock.calls[0];
    expect(url).toBe("/api/sessions");
    expect(JSON.parse(opts.body)).toEqual({ username: "ada", password: "s3cret" });
  });

  it("shows the server's error message on failed login", async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: false, error: "Incorrect username or password." }) })
    );
    const onLogin = vi.fn();

    render(<LoginModal onClose={noop} onLogin={onLogin} onSignupClick={noop} />);
    await userEvent.type(screen.getByLabelText(/Username/), "ada");
    await userEvent.type(screen.getByLabelText(/Password/), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Log In" }));

    expect(await screen.findByText("Incorrect username or password.")).toBeInTheDocument();
    expect(onLogin).not.toHaveBeenCalled();
  });

  it("requires both fields before submitting", async () => {
    const spy = vi.fn();
    global.fetch = spy;
    render(<LoginModal onClose={noop} onLogin={noop} onSignupClick={noop} />);
    await userEvent.click(screen.getByRole("button", { name: "Log In" }));

    expect(await screen.findByText(/Enter your username and password/)).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it("clicking Sign Up calls onSignupClick", async () => {
    global.fetch = vi.fn();
    const onSignupClick = vi.fn();
    render(<LoginModal onClose={noop} onLogin={noop} onSignupClick={onSignupClick} />);
    await userEvent.click(screen.getByRole("button", { name: "Sign Up" }));
    expect(onSignupClick).toHaveBeenCalled();
  });
});
