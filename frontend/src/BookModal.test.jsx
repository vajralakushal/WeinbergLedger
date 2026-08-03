import { useState } from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import BookModal from "./BookModal";

const BOOK = {
  ID: 1, TITLE: "QM", BORROWER: "Alex", LOCATION: "Shelf 1", IDENTIFIER: "",
};

// Mock thumbnail (404), history ([]), and capture PATCH calls.
function modalFetch(patchSpy) {
  return vi.fn((url, opts) => {
    if (String(url).includes("/thumbnail")) return Promise.resolve({ ok: false, status: 404 });
    if (String(url).includes("/history")) return Promise.resolve({ ok: true, json: () => Promise.resolve([]) });
    if (opts?.method === "PATCH") {
      patchSpy(url, opts);
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ ok: true }) });
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
}

// Stateful wrapper so the editor name propagates like it does in App.
function Harness({ initialName = "" }) {
  const [name, setName] = useState(initialName);
  return (
    <BookModal
      book={BOOK}
      onClose={() => {}}
      onFieldUpdate={() => {}}
      editorName={name}
      onEditorNameChange={setName}
    />
  );
}

// Mock thumbnail (404), history ([]), and capture DELETE calls.
function delFetch(delSpy, ok = true) {
  return vi.fn((url, opts) => {
    if (String(url).includes("/thumbnail")) return Promise.resolve({ ok: false, status: 404 });
    if (String(url).includes("/history")) return Promise.resolve({ ok: true, json: () => Promise.resolve([]) });
    if (opts?.method === "DELETE") {
      delSpy(url, opts);
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ ok }) });
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
}

const noop = () => {};

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("BookModal name gate", () => {
  it("blocks editing when no name is set and the prompt is cancelled", async () => {
    const patchSpy = vi.fn();
    global.fetch = modalFetch(patchSpy);
    const promptSpy = vi.spyOn(window, "prompt").mockReturnValue(null); // user cancels

    render(<Harness initialName="" />);
    await userEvent.click(screen.getByText("Alex")); // click borrower value

    expect(promptSpy).toHaveBeenCalled();
    expect(screen.queryByRole("textbox")).toBeNull(); // no editor opened
    expect(patchSpy).not.toHaveBeenCalled();
  });

  it("opens the editor once a name is provided via the prompt", async () => {
    global.fetch = modalFetch(vi.fn());
    vi.spyOn(window, "prompt").mockReturnValue("Zoe");

    render(<Harness initialName="" />);
    await userEvent.click(screen.getByText("Alex"));

    expect(await screen.findByRole("textbox")).toBeInTheDocument();
  });

  it("sends the editor name in the PATCH body when saving an edit", async () => {
    const patchSpy = vi.fn();
    global.fetch = modalFetch(patchSpy);

    render(<Harness initialName="Kushal" />); // name already known
    await userEvent.click(screen.getByText("Alex"));

    const input = await screen.findByRole("textbox");
    await userEvent.clear(input);
    await userEvent.type(input, "Bob{Enter}");

    await waitFor(() => {
      const call = patchSpy.mock.calls.find(([url]) =>
        String(url).includes("/api/book/1/borrower")
      );
      expect(call).toBeTruthy();
      expect(String(call[0]).startsWith("/api/")).toBe(true); // relative path
      const body = JSON.parse(call[1].body);
      expect(body).toMatchObject({ name: "Bob", editor: "Kushal" });
    });
  });
});

describe("BookModal remove", () => {
  it("requires a name — cancelling the prompt blocks removal", async () => {
    const delSpy = vi.fn();
    global.fetch = delFetch(delSpy);
    vi.spyOn(window, "prompt").mockReturnValue(null);
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);

    render(
      <BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={noop}
                 editorName="" onEditorNameChange={noop} />
    );
    await userEvent.click(screen.getByRole("button", { name: /Remove book/ }));

    expect(delSpy).not.toHaveBeenCalled();
    expect(confirmSpy).not.toHaveBeenCalled(); // never got past the name gate
  });

  it("aborts removal if the confirm dialog is declined", async () => {
    const delSpy = vi.fn();
    global.fetch = delFetch(delSpy);
    vi.spyOn(window, "confirm").mockReturnValue(false);

    render(
      <BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={noop}
                 editorName="Kushal" onEditorNameChange={noop} />
    );
    await userEvent.click(screen.getByRole("button", { name: /Remove book/ }));

    expect(delSpy).not.toHaveBeenCalled();
  });

  it("deletes the book with the editor name and calls onRemove when confirmed", async () => {
    const delSpy = vi.fn();
    const onRemove = vi.fn();
    global.fetch = delFetch(delSpy);
    vi.spyOn(window, "confirm").mockReturnValue(true);

    render(
      <BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={onRemove}
                 editorName="Kushal" onEditorNameChange={noop} />
    );
    await userEvent.click(screen.getByRole("button", { name: /Remove book/ }));

    await waitFor(() => expect(delSpy).toHaveBeenCalled());
    const [url, opts] = delSpy.mock.calls[0];
    expect(url).toBe("/api/book/1");
    expect(opts.method).toBe("DELETE");
    expect(JSON.parse(opts.body)).toMatchObject({ editor: "Kushal" });
    expect(onRemove).toHaveBeenCalledWith(1);
  });
});
