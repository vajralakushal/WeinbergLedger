import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, afterEach } from "vitest";
import SignupView from "./SignupView";

const noop = () => {};

afterEach(() => {
  vi.restoreAllMocks();
});

async function fillForm() {
  await userEvent.type(screen.getByLabelText(/First Name/), "Ada");
  await userEvent.type(screen.getByLabelText(/Last Name/), "Lovelace");
  await userEvent.type(screen.getByLabelText(/Username/), "ada");
  await userEvent.type(screen.getByLabelText(/Password/), "s3cret123");
}

describe("SignupView", () => {
  it("submits the form (including the quiz answer) to /api/registrations", async () => {
    const spy = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      spy(url, opts);
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: true, user_id: 1234 }) });
    });

    render(<SignupView onBack={noop} onRegistered={noop} />);
    await fillForm();
    await userEvent.type(screen.getByLabelText(/speed of light/), "1");
    await userEvent.click(screen.getByRole("button", { name: /Submit Registration/ }));

    await waitFor(() => expect(spy).toHaveBeenCalled());
    const [url, opts] = spy.mock.calls[0];
    expect(url).toBe("/api/registrations");
    expect(JSON.parse(opts.body)).toMatchObject({
      first_name: "Ada", last_name: "Lovelace", username: "ada", password: "s3cret123", light_speed: "1",
    });
    expect(await screen.findByText(/has been submitted/)).toBeInTheDocument();
  });

  it("shows 'registration has been denied' when the server denies the quiz answer", async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: false, denied: true, error: "Registration has been denied." }) })
    );

    render(<SignupView onBack={noop} onRegistered={noop} />);
    await fillForm();
    await userEvent.type(screen.getByLabelText(/speed of light/), "42");
    await userEvent.click(screen.getByRole("button", { name: /Submit Registration/ }));

    expect(await screen.findByText("Registration has been denied.")).toBeInTheDocument();
  });

  it("requires the core fields before submitting", async () => {
    const spy = vi.fn();
    global.fetch = spy;
    render(<SignupView onBack={noop} onRegistered={noop} />);
    await userEvent.click(screen.getByRole("button", { name: /Submit Registration/ }));

    expect(await screen.findByText(/are all required/)).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it("clicking Back to Log In after success calls onRegistered", async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: true, user_id: 1 }) })
    );
    const onRegistered = vi.fn();

    render(<SignupView onBack={noop} onRegistered={onRegistered} />);
    await fillForm();
    await userEvent.type(screen.getByLabelText(/speed of light/), "1");
    await userEvent.click(screen.getByRole("button", { name: /Submit Registration/ }));

    await userEvent.click(await screen.findByRole("button", { name: /Back to Log In/ }));
    expect(onRegistered).toHaveBeenCalled();
  });
});
