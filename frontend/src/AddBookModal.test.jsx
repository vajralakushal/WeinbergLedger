import { render, screen, waitFor, fireEvent } from "@testing-library/react";
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
    render(<AddBookModal onClose={noop} onAdded={noop} authToken="tok" />);

    await userEvent.click(screen.getByRole("button", { name: /Add book/ }));

    expect(await screen.findByText(/Title and Owner are required/)).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it("posts the new book with the bearer token and reports success", async () => {
    const spy = vi.fn();
    const onAdded = vi.fn();
    global.fetch = addFetch(spy, { ok: true, book: { ID: 42, TITLE: "Real Analysis" } });

    render(<AddBookModal onClose={noop} onAdded={onAdded} authToken="tok-123" />);
    await userEvent.type(screen.getByLabelText(/Title/), "Real Analysis");
    await userEvent.type(screen.getByLabelText(/Owner/), "Alex Lu");
    await userEvent.type(screen.getByLabelText(/Creator/), "Rudin");
    await userEvent.click(screen.getByRole("button", { name: /Add book/ }));

    await waitFor(() => expect(spy).toHaveBeenCalled());
    const [url, opts] = spy.mock.calls[0];
    expect(url).toBe("/api/book");
    expect(opts.method).toBe("POST");
    expect(opts.headers.Authorization).toBe("Bearer tok-123");
    const body = JSON.parse(opts.body);
    expect(body).toMatchObject({ TITLE: "Real Analysis", OWNER: "Alex Lu", CREATOR: "Rudin" });
    expect(body.editor).toBeUndefined(); // no client-supplied identity anymore

    expect(await screen.findByText(/Added .*Real Analysis.* \(ID 42\)/)).toBeInTheDocument();
    expect(onAdded).toHaveBeenCalledWith({ ID: 42, TITLE: "Real Analysis" });
  });

  it("auto-populates fields from an identifier lookup", async () => {
    global.fetch = vi.fn((url) => {
      if (String(url).includes("/api/lookup")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ ok: true, book: { TITLE: "Quantum Mechanics", CREATOR: "Griffiths" } }),
        });
      }
      return Promise.reject(new Error(`unhandled fetch: ${url}`));
    });

    render(<AddBookModal onClose={noop} onAdded={noop} authToken="tok" />);
    await userEvent.type(screen.getByPlaceholderText(/auto-fill/), "9780131118928");
    await userEvent.click(screen.getByRole("button", { name: /Look up/ }));

    await waitFor(() => {
      expect(screen.getByLabelText(/Title/)).toHaveValue("Quantum Mechanics");
    });
    expect(screen.getByLabelText(/Creator/)).toHaveValue("Griffiths");
  });
});

describe("AddBookModal bulk CSV", () => {
  it("imports pasted CSV with the bearer token and shows a report", async () => {
    const spy = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      if (String(url).includes("/api/books/bulk")) {
        spy(url, opts);
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            ok: true,
            added: [{ line: 2, id: 5, title: "Algebra" }],
            skipped: [{ line: 3, reason: "No ISBN or LC" }],
          }),
        });
      }
      return Promise.reject(new Error(`unhandled fetch: ${url}`));
    });

    render(<AddBookModal onClose={noop} onAdded={noop} authToken="tok-123" />);
    await userEvent.click(screen.getByRole("button", { name: /Bulk CSV/ }));

    fireEvent.change(screen.getByRole("textbox"), {
      target: { value: "Owner,Title,Identifier\nAlex,Algebra,ISBN : 1" },
    });
    await userEvent.click(screen.getByRole("button", { name: /Import CSV/ }));

    await waitFor(() => expect(spy).toHaveBeenCalled());
    const [, opts] = spy.mock.calls[0];
    expect(opts.headers.Authorization).toBe("Bearer tok-123");
    const body = JSON.parse(opts.body);
    expect(body.csv).toContain("Owner,Title,Identifier");
    expect(body.editor).toBeUndefined();

    expect(await screen.findByText(/Added 1 book/)).toBeInTheDocument();
    expect(screen.getByText(/Line 3: No ISBN or LC/)).toBeInTheDocument();
  });

  it("offers to add identifier-less rows anyway, and resubmits just those on confirm", async () => {
    const spy = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      const body = JSON.parse(opts.body);
      spy(body);
      if (!body.force_no_identifier) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            ok: true,
            added: [],
            skipped: [{ line: 2, title: "Old Book", reason: "No ISBN or LC (and none found online)", missing_identifier: true }],
          }),
        });
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ ok: true, added: [{ line: 2, id: 9, title: "Old Book" }], skipped: [] }),
      });
    });
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);

    render(<AddBookModal onClose={noop} onAdded={noop} authToken="tok" />);
    await userEvent.click(screen.getByRole("button", { name: /Bulk CSV/ }));
    fireEvent.change(screen.getByRole("textbox"), {
      target: { value: "Owner,Title\nAlex,Old Book" },
    });
    await userEvent.click(screen.getByRole("button", { name: /Import CSV/ }));

    const retryBtn = await screen.findByRole("button", { name: /Add books without an identifier/ });
    await userEvent.click(retryBtn);

    expect(confirmSpy).toHaveBeenCalled();
    await waitFor(() => expect(spy).toHaveBeenCalledTimes(2));
    const secondCallBody = spy.mock.calls[1][0];
    expect(secondCallBody.force_no_identifier).toBe(true);
    expect(secondCallBody.csv).toContain("Old Book");

    expect(await screen.findByText(/Added 1 book/)).toBeInTheDocument();
    expect(screen.queryByText(/No ISBN or LC/)).toBeNull();
    expect(screen.queryByRole("button", { name: /Add books without an identifier/ })).toBeNull();
  });

  it("does not resubmit if the confirmation is declined", async () => {
    const spy = vi.fn();
    global.fetch = vi.fn((url, opts) => {
      spy(opts);
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({
          ok: true,
          added: [],
          skipped: [{ line: 2, title: "Old Book", reason: "No ISBN or LC (and none found online)", missing_identifier: true }],
        }),
      });
    });
    vi.spyOn(window, "confirm").mockReturnValue(false);

    render(<AddBookModal onClose={noop} onAdded={noop} authToken="tok" />);
    await userEvent.click(screen.getByRole("button", { name: /Bulk CSV/ }));
    fireEvent.change(screen.getByRole("textbox"), {
      target: { value: "Owner,Title\nAlex,Old Book" },
    });
    await userEvent.click(screen.getByRole("button", { name: /Import CSV/ }));

    const retryBtn = await screen.findByRole("button", { name: /Add books without an identifier/ });
    await userEvent.click(retryBtn);

    expect(spy).toHaveBeenCalledTimes(1); // only the original import call
  });
});
