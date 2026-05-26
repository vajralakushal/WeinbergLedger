import { useState, useCallback } from "react";
import "./App.css";
import BookModal from "./BookModal";

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

  const runSearch = useCallback(async () => {
    const q = query.trim();
    if (!q) return;
    setLoading(true);
    setError(null);
    setRows(null);
    try {
      const res = await fetch(
        `http://localhost:5004/api/search?q=${encodeURIComponent(q)}`
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

  // Sync borrower change back into the results table
  const handleBorrowerUpdate = useCallback((id, name) => {
    setRows((prev) =>
      prev?.map((r) => r.ID === id ? { ...r, BORROWER: name } : r) ?? prev
    );
    setSelectedBook((prev) => prev?.ID === id ? { ...prev, BORROWER: name } : prev);
  }, []);

  return (
    <div className="page">
      <div className="search-card">
        <h1 className="title">Weinberg Library Search</h1>

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

      {selectedBook && (
        <BookModal
          book={selectedBook}
          onClose={() => setSelectedBook(null)}
          onBorrowerUpdate={handleBorrowerUpdate}
        />
      )}
    </div>
  );
}
