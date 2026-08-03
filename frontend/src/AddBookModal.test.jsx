import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, afterEach } from "vitest";
import AddBookModal from "./AddBookModal";

function addFetch(spy, resp = { ok: true, book: { ID: 99, TITLE: "T" } }) {
  return vi.fn((url, opts) => {
    if (opts?.method === "POST") {
      spy(url, opts);
      return Promise.resolve({ ok: true, status: 201, json: () => Promise.resolve(resp) });
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
}

const noop = () => {};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("AddBookModal", () => {
  it("requires title and owner before submitting", async () => {
    const spy = vi.fn();
    global.fetch = addFetch(spy);
    render(<AddBookModal onClose={noop} onAdded={noop} editorName="Kushal" onEditorNameChange={noop} />);

    await userEvent.click(screen.getByRole("button", { name: /Add book/ }));

    expect(await screen.findByText(/Title and Owner are required/)).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it("requires a name — cancelling the prompt aborts the add", async () => {
    const spy = vi.fn();
    global.fetch = addFetch(spy);
    vi.spyOn(window, "prompt").mockReturnValue(null); // user cancels

    render(<AddBookModal onClose={noop} onAdded={noop} editorName="" onEditorNameChange={noop} />);
    await userEvent.type(screen.getByLabelText(/Title/), "New Book");
    await userEvent.type(screen.getByLabelText(/Owner/), "Alex Lu");
    await userEvent.click(screen.getByRole("button", { name: /Add book/ }));

    expect(spy).not.toHaveBeenCalled();
  });

  it("posts the new book with the editor name and reports success", async () => {
    const spy = vi.fn();
    const onAdded = vi.fn();
    global.fetch = addFetch(spy, { ok: true, book: { ID: 42, TITLE: "Real Analysis" } });

    render(<AddBookModal onClose={noop} onAdded={onAdded} editorName="Kushal" onEditorNameChange={noop} />);
    await userEvent.type(screen.getByLabelText(/Title/), "Real Analysis");
    await userEvent.type(screen.getByLabelText(/Owner/), "Alex Lu");
    await userEvent.type(screen.getByLabelText(/Creator/), "Rudin");
    await userEvent.click(screen.getByRole("button", { name: /Add book/ }));

    await waitFor(() => expect(spy).toHaveBeenCalled());
    const [url, opts] = spy.mock.calls[0];
    expect(url).toBe("/api/book");
    expect(opts.method).toBe("POST");
    const body = JSON.parse(opts.body);
    expect(body).toMatchObject({
      TITLE: "Real Analysis", OWNER: "Alex Lu", CREATOR: "Rudin", editor: "Kushal",
    });

    expect(await screen.findByText(/Added .*Real Analysis.* \(ID 42\)/)).toBeInTheDocument();
    expect(onAdded).toHaveBeenCalledWith({ ID: 42, TITLE: "Real Analysis" });
  });
});
