import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import BookModal from "./BookModal";

const BOOK = {
  ID: 1, TITLE: "QM", BORROWER: "Alex", LOCATION: "Shelf 1", IDENTIFIER: "",
};

const USER = { user_id: 42, username: "kushal", first_name: "Kushal", last_name: "V", admin_status: false };

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

describe("BookModal editing gate", () => {
  it("does not let a logged-out visitor open the editor", async () => {
    const patchSpy = vi.fn();
    global.fetch = modalFetch(patchSpy);

    render(<BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} currentUser={null} authToken="" />);
    await userEvent.click(screen.getByText("Alex")); // click borrower value

    expect(screen.queryByRole("textbox")).toBeNull(); // no editor opened
    expect(patchSpy).not.toHaveBeenCalled();
  });

  it("opens the editor for a logged-in user", async () => {
    global.fetch = modalFetch(vi.fn());

    render(<BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} currentUser={USER} authToken="tok" />);
    await userEvent.click(screen.getByText("Alex"));

    expect(await screen.findByRole("textbox")).toBeInTheDocument();
  });

  it("sends the bearer token (not an editor name) in the PATCH request", async () => {
    const patchSpy = vi.fn();
    global.fetch = modalFetch(patchSpy);

    render(<BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} currentUser={USER} authToken="tok-123" />);
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
      expect(call[1].headers.Authorization).toBe("Bearer tok-123");
      const body = JSON.parse(call[1].body);
      expect(body).toMatchObject({ name: "Bob" });
      expect(body.editor).toBeUndefined(); // no client-supplied identity anymore
    });
  });
});

describe("BookModal remove", () => {
  it("does not show the remove button to a logged-out visitor", async () => {
    global.fetch = delFetch(vi.fn());
    render(<BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={noop} currentUser={null} authToken="" />);
    await screen.findByText("No cover on file"); // let the thumbnail/history effects settle
    expect(screen.queryByRole("button", { name: /Remove book/ })).toBeNull();
  });

  it("aborts removal if the confirm dialog is declined", async () => {
    const delSpy = vi.fn();
    global.fetch = delFetch(delSpy);
    vi.spyOn(window, "confirm").mockReturnValue(false);

    render(
      <BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={noop}
                 currentUser={USER} authToken="tok" />
    );
    await userEvent.click(screen.getByRole("button", { name: /Remove book/ }));

    expect(delSpy).not.toHaveBeenCalled();
  });

  it("deletes the book with the bearer token and calls onRemove when confirmed", async () => {
    const delSpy = vi.fn();
    const onRemove = vi.fn();
    global.fetch = delFetch(delSpy);
    vi.spyOn(window, "confirm").mockReturnValue(true);

    render(
      <BookModal book={BOOK} onClose={noop} onFieldUpdate={noop} onRemove={onRemove}
                 currentUser={USER} authToken="tok-123" />
    );
    await userEvent.click(screen.getByRole("button", { name: /Remove book/ }));

    await waitFor(() => expect(delSpy).toHaveBeenCalled());
    const [url, opts] = delSpy.mock.calls[0];
    expect(url).toBe("/api/book/1");
    expect(opts.method).toBe("DELETE");
    expect(opts.headers.Authorization).toBe("Bearer tok-123");
    expect(onRemove).toHaveBeenCalledWith(1);
  });
});
