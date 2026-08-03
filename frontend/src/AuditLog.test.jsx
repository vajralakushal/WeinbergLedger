import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi } from "vitest";
import AuditLog from "./AuditLog";

const ROWS = [
  { BOOK_ID: 2, BOOK_TITLE: "Topology", FIELD: "LOCATION", OLD_VALUE: null, NEW_VALUE: "S9", EDITOR: "Yasin", IP: "1.1.1.1", TIMESTAMP: "2026-08-03T02:00:00Z" },
  { BOOK_ID: 1, BOOK_TITLE: "Quantum Mechanics", FIELD: "BORROWER", OLD_VALUE: null, NEW_VALUE: "Bob", EDITOR: "Kushal", IP: "2.2.2.2", TIMESTAMP: "2026-08-03T01:00:00Z" },
  { BOOK_ID: 1, BOOK_TITLE: "Quantum Mechanics", FIELD: "LOCATION", OLD_VALUE: "S1", NEW_VALUE: "S2", EDITOR: "Kushal", IP: "2.2.2.2", TIMESTAMP: "2026-08-03T00:00:00Z" },
];

function auditFetch(rows) {
  return vi.fn((url) => {
    if (String(url).includes("/api/audit")) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve(rows) });
    }
    return Promise.reject(new Error(`unhandled fetch: ${url}`));
  });
}

describe("AuditLog", () => {
  it("loads and renders every audit entry from /api/audit", async () => {
    global.fetch = auditFetch(ROWS);
    render(<AuditLog onBack={() => {}} />);

    expect(await screen.findByText("Topology")).toBeInTheDocument();
    // "Yasin" shows up both as a table cell and a filter option
    expect(screen.getByRole("option", { name: "Yasin" })).toBeInTheDocument();
    expect(screen.getByText(/3 of 3 entries/)).toBeInTheDocument();
  });

  it("filters entries by person", async () => {
    global.fetch = auditFetch(ROWS);
    render(<AuditLog onBack={() => {}} />);
    await screen.findByText("Topology");

    await userEvent.selectOptions(screen.getByRole("combobox"), "Kushal");

    expect(screen.getByText(/2 of 3 entries/)).toBeInTheDocument();
    // Yasin's only book drops out of the table
    expect(screen.queryByText("Topology")).toBeNull();
  });

  it("filters entries by free text", async () => {
    global.fetch = auditFetch(ROWS);
    render(<AuditLog onBack={() => {}} />);
    await screen.findByText("Topology");

    await userEvent.type(screen.getByPlaceholderText(/Filter by book/), "Topology");

    await waitFor(() => {
      expect(screen.getByText(/1 of 3 entries/)).toBeInTheDocument();
    });
  });

  it("shows an empty-state message when there are no entries", async () => {
    global.fetch = auditFetch([]);
    render(<AuditLog onBack={() => {}} />);
    expect(await screen.findByText(/No edits have been recorded yet/)).toBeInTheDocument();
  });
});
