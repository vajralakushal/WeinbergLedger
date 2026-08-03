import { useState, useEffect, useCallback } from "react";
import "./App.css";
import BookModal from "./BookModal";
import AuditLog from "./AuditLog";
import AddBookModal from "./AddBookModal";

const EDITOR_NAME_KEY = "weinberg.editorName";

const COLUMNS = [
  { key: "ID",            label: "ID" },
  { key: "OWNER",         label: "Owner" },
  { key: "BORROWER",      label: "Borrower" },
  { key: "LOCATION",      label: "Location" },
  { key: "TITLE",         label: "Title" },
  { key: "CREATOR",       label: "Creator" },
  { key: "PUBLISHER",     label: "Publisher" },
  { key: "SERIES",        label: "Series" },
  { key: "SUBJECT",       label: "Subject" },
  { key: "CREATION_DATE", label: "Year" },
  { key: "IDENTIFIER",    label: "Identifier" },
];

export default function App() {
  const [query, setQuery]           = useState("");
  const [rows, setRows]             = useState(null);
  const [loading, setLoading]       = useState(false);
  const [error, setError]           = useState(null);
  const [selectedBook, setSelectedBook] = useState(null);
  const [view, setView]             = useState("search"); // "search" | "audit"
  const [showAddBook, setShowAddBook] = useState(false);

  // Audit trail: who is editing (persisted per browser) and their IP.
  const [editorName, setEditorNameState] = useState(
    () => localStorage.getItem(EDITOR_NAME_KEY) ?? ""
  );
  const [clientIp, setClientIp] = useState(null);

  const setEditorName = useCallback((name) => {
    const trimmed = name.trim();
    setEditorNameState(trimmed);
    if (trimmed) localStorage.setItem(EDITOR_NAME_KEY, trimmed);
    else localStorage.removeItem(EDITOR_NAME_KEY);
  }, []);

  useEffect(() => {
    fetch("/api/whoami")
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => data && setClientIp(data.ip))
      .catch(() => setClientIp(null));
  }, []);

  const runSearch = useCallback(async () => {
    const q = query.trim();
    if (!q) return;
    setLoading(true);
    setError(null);
    setRows(null);
    try {
      const res = await fetch(
        `/api/search?q=${encodeURIComponent(q)}`
      );
      if (!res.ok) throw new Error(`Server error ${res.status}`);
      setRows(await res.json());
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [query]);

  const handleKey = (e) => {
    if (e.key === "Enter") runSearch();
  };

  // Sync any editable field change back into the results table and open modal
  const handleFieldUpdate = useCallback((id, fieldKey, value) => {
    setRows((prev) =>
      prev?.map((r) => r.ID === id ? { ...r, [fieldKey]: value } : r) ?? prev
    );
    setSelectedBook((prev) => prev?.ID === id ? { ...prev, [fieldKey]: value } : prev);
  }, []);

  // Drop a removed book from the current results and close the modal.
  const handleRemove = useCallback((id) => {
    setRows((prev) => prev?.filter((r) => r.ID !== id) ?? prev);
    setSelectedBook(null);
  }, []);

  // Show a newly added book at the top of the current results.
  const handleAdded = useCallback((newBook) => {
    setRows((prev) => (prev ? [newBook, ...prev] : prev));
  }, []);

  // Return to a fresh home screen from anywhere.
  const goHome = useCallback(() => {
    setView("search");
    setSelectedBook(null);
    setShowAddBook(false);
    setRows(null);
    setError(null);
    setQuery("");
  }, []);

  return (
    <div className="page">
      {view === "audit" ? (
        <AuditLog onBack={goHome} />
      ) : (
      <div className="search-card">
        <div className="header-row">
          <h1
            className="title clickable-title"
            onClick={goHome}
            title="Go to home"
          >
            Weinberg Library Search
          </h1>
          <button className="add-book-open" onClick={() => setShowAddBook(true)}>
            ➕ Add book
          </button>
        </div>

        <div className="search-row">
          <input
            className="search-input"
            type="text"
            placeholder="Search params"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKey}
            autoFocus
          />
          <button className="search-btn" onClick={runSearch} aria-label="Search">
            🔍
          </button>
        </div>

        {loading && <p className="status">Searching…</p>}
        {error   && <p className="status error">Error: {error}</p>}

        {rows !== null && (
          rows.length === 0
            ? <p className="status">No results found.</p>
            : (
              <div className="results">
                <p className="result-count">
                  {rows.length} result{rows.length !== 1 ? "s" : ""}
                </p>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        {COLUMNS.map((c) => (
                          <th key={c.key}>{c.label}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((row) => (
                        <tr
                          key={row.ID}
                          className="clickable-row"
                          onClick={() => setSelectedBook(row)}
                        >
                          {COLUMNS.map((c) => (
                            <td key={c.key}>{row[c.key] ?? ""}</td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )
        )}
      </div>
      )}

      {selectedBook && (
        <BookModal
          book={selectedBook}
          onClose={() => setSelectedBook(null)}
          onFieldUpdate={handleFieldUpdate}
          onRemove={handleRemove}
          editorName={editorName}
          onEditorNameChange={setEditorName}
        />
      )}

      {showAddBook && (
        <AddBookModal
          onClose={() => setShowAddBook(false)}
          onAdded={handleAdded}
          editorName={editorName}
          onEditorNameChange={setEditorName}
        />
      )}

      <footer className="site-footer">
        <span>
          Editing as:{" "}
          {editorName
            ? <strong>{editorName}</strong>
            : <em>not set — you'll be asked when you edit</em>}
          {editorName && (
            <button
              className="footer-link"
              onClick={() => {
                const next = window.prompt("Your name (for the edit record):", editorName);
                if (next !== null) setEditorName(next);
              }}
            >
              change
            </button>
          )}
        </span>
        {view === "search" && (
          <button className="footer-link" onClick={() => setView("audit")}>
            View audit log →
          </button>
        )}
        <span>Your IP: {clientIp ?? "…"}</span>
      </footer>
    </div>
  );
}
