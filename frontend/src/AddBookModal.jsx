import { useState, useEffect, useCallback } from "react";
import "./AddBookModal.css";
import { ensureEditorName } from "./ensureName";

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

export default function AddBookModal({ onClose, onAdded, editorName, onEditorNameChange }) {
  const [values, setValues]   = useState(EMPTY);
  const [error, setError]     = useState(null);
  const [success, setSuccess] = useState(null);
  const [saving, setSaving]   = useState(false);

  // Escape closes the modal.
  useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const setField = (key, value) => setValues((prev) => ({ ...prev, [key]: value }));

  const submit = useCallback(async () => {
    setError(null);
    if (!values.TITLE.trim() || !values.OWNER.trim()) {
      setError("Title and Owner are required.");
      return;
    }
    const name = ensureEditorName(editorName, onEditorNameChange);
    if (!name) return; // no name → abort

    setSaving(true);
    try {
      const res = await fetch("/api/book", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...values, editor: name }),
      });
      const data = await res.json();
      if (!data.ok) {
        setError(data.error ?? "Could not add the book.");
        return;
      }
      setSuccess(`Added “${data.book.TITLE}” (ID ${data.book.ID}).`);
      onAdded?.(data.book);
      setValues(EMPTY); // ready for the next entry
    } catch {
      setError("Could not reach server.");
    } finally {
      setSaving(false);
    }
  }, [values, editorName, onEditorNameChange, onAdded]);

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card add-book-card">
        <h2 className="add-book-title">Add a book</h2>

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
      </div>
    </div>
  );
}
