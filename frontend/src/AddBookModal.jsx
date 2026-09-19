import { useState, useEffect, useCallback } from "react";
import "./AddBookModal.css";
import { authHeaders } from "./api";

// DB columns a user can set, with labels. Order = form order.
const FIELDS = [
  { key: "TITLE",         label: "Title",     required: true },
  { key: "OWNER",         label: "Owner",     required: true },
  { key: "CREATOR",       label: "Creator" },
  { key: "PUBLISHER",     label: "Publisher" },
  { key: "SERIES",        label: "Series" },
  { key: "SUBJECT",       label: "Subject" },
  { key: "CREATION_DATE", label: "Year" },
  { key: "LOCATION",      label: "Location / shelf" },
  { key: "BORROWER",      label: "Borrower" },
  { key: "IDENTIFIER",    label: "Identifier" },
];

const EMPTY = Object.fromEntries(FIELDS.map((f) => [f.key, ""]));

// Keep only our known fields, as non-empty strings.
function fromLookup(book) {
  const out = {};
  for (const f of FIELDS) {
    const v = book?.[f.key];
    if (v != null && String(v) !== "") out[f.key] = String(v);
  }
  return out;
}

export default function AddBookModal({ onClose, onAdded, authToken }) {
  const [mode, setMode] = useState("single"); // "single" | "bulk"

  // Single-book form
  const [values, setValues]   = useState(EMPTY);
  const [error, setError]     = useState(null);
  const [success, setSuccess] = useState(null);
  const [saving, setSaving]   = useState(false);

  // Identifier lookup (auto-populate)
  const [idType, setIdType]         = useState("isbn");
  const [idValue, setIdValue]       = useState("");
  const [lookupMsg, setLookupMsg]   = useState(null);
  const [lookingUp, setLookingUp]   = useState(false);

  // Bulk CSV
  const [csvText, setCsvText]       = useState("");
  const [bulkReport, setBulkReport] = useState(null);
  const [bulkError, setBulkError]   = useState(null);
  const [importing, setImporting]   = useState(false);

  useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const setField = (key, value) => setValues((prev) => ({ ...prev, [key]: value }));

  // ── Identifier lookup ──
  const lookup = useCallback(async () => {
    const val = idValue.trim();
    if (!val) return;
    setLookupMsg(null);
    setLookingUp(true);
    try {
      const res = await fetch(`/api/lookup?${idType}=${encodeURIComponent(val)}`);
      const data = await res.json();
      if (!res.ok || !data.ok) {
        setLookupMsg(data.error ?? "No match found.");
        return;
      }
      setValues((prev) => ({ ...prev, ...fromLookup(data.book) }));
      setLookupMsg("Fields populated — review and edit as needed.");
    } catch {
      setLookupMsg("Could not reach server.");
    } finally {
      setLookingUp(false);
    }
  }, [idType, idValue]);

  // ── Single add ──
  const submit = useCallback(async () => {
    setError(null);
    if (!values.TITLE.trim() || !values.OWNER.trim()) {
      setError("Title and Owner are required.");
      return;
    }

    setSaving(true);
    try {
      const res = await fetch("/api/book", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeaders(authToken) },
        body: JSON.stringify(values),
      });
      const data = await res.json();
      if (!data.ok) {
        setError(data.error ?? "Could not add the book.");
        return;
      }
      setSuccess(`Added “${data.book.TITLE}” (ID ${data.book.ID}).`);
      onAdded?.(data.book);
      setValues(EMPTY);
      setIdValue("");
      setLookupMsg(null);
    } catch {
      setError("Could not reach server.");
    } finally {
      setSaving(false);
    }
  }, [values, authToken, onAdded]);

  // ── Bulk import ──
  const onFile = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => setCsvText(String(reader.result));
    reader.readAsText(file);
  };

  const importBulk = useCallback(async () => {
    setBulkError(null);
    setBulkReport(null);
    if (!csvText.trim()) {
      setBulkError("Paste or upload some CSV first.");
      return;
    }

    setImporting(true);
    try {
      const res = await fetch("/api/books/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeaders(authToken) },
        body: JSON.stringify({ csv: csvText }),
      });
      const data = await res.json();
      if (!data.ok) {
        setBulkError(data.error ?? "Import failed.");
        return;
      }
      setBulkReport(data);
      data.added?.forEach((b) => onAdded?.({ ...EMPTY, ID: b.id, TITLE: b.title }));
    } catch {
      setBulkError("Could not reach server.");
    } finally {
      setImporting(false);
    }
  }, [csvText, authToken, onAdded]);

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card add-book-card">
        <h2 className="add-book-title">Add books</h2>

        <div className="add-book-tabs">
          <button
            className={`add-book-tab ${mode === "single" ? "active" : ""}`}
            onClick={() => setMode("single")}
          >
            Single book
          </button>
          <button
            className={`add-book-tab ${mode === "bulk" ? "active" : ""}`}
            onClick={() => setMode("bulk")}
          >
            Bulk CSV
          </button>
        </div>

        {mode === "single" ? (
          <>
            <div className="lookup-row">
              <select
                className="lookup-type"
                value={idType}
                onChange={(e) => setIdType(e.target.value)}
                aria-label="Identifier type"
              >
                <option value="isbn">ISBN</option>
                <option value="lccn">LCCN</option>
                <option value="oclc">OCLC</option>
              </select>
              <input
                className="lookup-input"
                placeholder="Enter an identifier to auto-fill…"
                value={idValue}
                onChange={(e) => setIdValue(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") lookup(); }}
              />
              <button className="lookup-btn" onClick={lookup} disabled={lookingUp}>
                {lookingUp ? "Looking up…" : "Look up"}
              </button>
            </div>
            {lookupMsg && <p className="lookup-msg">{lookupMsg}</p>}

            <div className="add-book-form">
              {FIELDS.map(({ key, label, required }) => (
                <label key={key} className="add-book-field">
                  <span className="add-book-label">
                    {label}{required && <span className="req"> *</span>}
                  </span>
                  <input
                    className="add-book-input"
                    value={values[key]}
                    onChange={(e) => setField(key, e.target.value)}
                  />
                </label>
              ))}
            </div>

            {error   && <p className="status error">{error}</p>}
            {success && <p className="add-book-success">{success}</p>}

            <div className="add-book-actions">
              <button className="add-book-submit" onClick={submit} disabled={saving}>
                {saving ? "Adding…" : "Add book"}
              </button>
              <button className="add-book-cancel" onClick={onClose}>Done</button>
            </div>
          </>
        ) : (
          <>
            <p className="bulk-help">
              Paste CSV with the columns <code>Owner, Title, … Identifier</code> (same
              layout as the library spreadsheet). Each row needs a Title, an Owner, and
              an ISBN or LC in the Identifier field — a missing ISBN is looked up online
              when possible, otherwise the row is skipped.
            </p>

            <input type="file" accept=".csv,text/csv" onChange={onFile} className="bulk-file" />
            <textarea
              className="bulk-textarea"
              placeholder="Owner,Borrower,Shelf,DD,Title,Creator,Publisher,Edition,Series,Notes,Subject,Creation Date,Identifier&#10;…"
              value={csvText}
              onChange={(e) => setCsvText(e.target.value)}
              rows={8}
            />

            {bulkError && <p className="status error">{bulkError}</p>}

            {bulkReport && (
              <div className="bulk-report">
                <p className="add-book-success">Added {bulkReport.added.length} book(s).</p>
                {bulkReport.skipped.length > 0 && (
                  <>
                    <p className="bulk-skipped-title">
                      Skipped {bulkReport.skipped.length}:
                    </p>
                    <ul className="bulk-skipped-list">
                      {bulkReport.skipped.map((s, i) => (
                        <li key={i}>Line {s.line}: {s.reason}</li>
                      ))}
                    </ul>
                  </>
                )}
              </div>
            )}

            <div className="add-book-actions">
              <button className="add-book-submit" onClick={importBulk} disabled={importing}>
                {importing ? "Importing…" : "Import CSV"}
              </button>
              <button className="add-book-cancel" onClick={onClose}>Done</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
