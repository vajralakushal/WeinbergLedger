import { useState, useEffect, useCallback } from "react";
import "./App.css";
import BookModal from "./BookModal";
import AuditLog from "./AuditLog";
import AddBookModal from "./AddBookModal";
import LoginModal from "./LoginModal";
import ChangePasswordModal from "./ChangePasswordModal";
import SignupView from "./SignupView";
import UsersDashboard from "./UsersDashboard";
import UserMenu from "./UserMenu";
import { authHeaders } from "./api";

const AUTH_TOKEN_KEY = "weinberg.authToken";

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

// Fields a search can be isolated to — mirrors Book::SEARCH_FIELDS on the backend.
const SEARCH_FIELDS = COLUMNS.filter((c) => c.key !== "ID");

export default function App() {
  const [query, setQuery]           = useState("");
  const [searchFields, setSearchFields] = useState([]); // empty = search all fields
  const [rows, setRows]             = useState(null);
  const [loading, setLoading]       = useState(false);
  const [error, setError]           = useState(null);
  const [selectedBook, setSelectedBook] = useState(null);
  const [view, setView]             = useState("search"); // "search" | "audit" | "signup" | "admin"
  const [showAddBook, setShowAddBook] = useState(false);

  // Auth: bearer token (persisted) + the account it belongs to.
  const [authToken, setAuthTokenState] = useState(
    () => localStorage.getItem(AUTH_TOKEN_KEY) ?? ""
  );
  const [currentUser, setCurrentUser] = useState(null);
  const [showLogin, setShowLogin]     = useState(false);
  const [showChangePassword, setShowChangePassword] = useState(false);

  const [clientIp, setClientIp] = useState(null);

  const setAuthToken = useCallback((token) => {
    setAuthTokenState(token);
    if (token) localStorage.setItem(AUTH_TOKEN_KEY, token);
    else localStorage.removeItem(AUTH_TOKEN_KEY);
  }, []);

  // Restore the session on load (and drop a stale/expired token quietly).
  useEffect(() => {
    if (!authToken) return;
    fetch("/api/me", { headers: authHeaders(authToken) })
      .then((res) => (res.ok ? res.json() : null))
      .then((user) => {
        if (user) setCurrentUser(user);
        else setAuthToken("");
      })
      .catch(() => {});
    // Only ever needs to run for the token this component mounted with.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    fetch("/api/whoami")
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => data && setClientIp(data.ip))
      .catch(() => setClientIp(null));
  }, []);

  const handleLogin = useCallback((token, user) => {
    setAuthToken(token);
    setCurrentUser(user);
    setShowLogin(false);
    if (user.must_change_password) setShowChangePassword(true);
  }, [setAuthToken]);

  const handleLogout = useCallback(() => {
    fetch("/api/sessions", { method: "DELETE", headers: authHeaders(authToken) }).catch(() => {});
    setAuthToken("");
    setCurrentUser(null);
    setView((v) => (v === "admin" ? "search" : v));
  }, [authToken, setAuthToken]);

  const runSearch = useCallback(async () => {
    const q = query.trim();
    if (!q) return;
    setLoading(true);
    setError(null);
    setRows(null);
    try {
      const params = new URLSearchParams({ q });
      searchFields.forEach((f) => params.append("fields[]", f));
      const res = await fetch(`/api/search?${params.toString()}`);
      if (!res.ok) throw new Error(`Server error ${res.status}`);
      setRows(await res.json());
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [query, searchFields]);

  const toggleSearchField = useCallback((key) => {
    setSearchFields((prev) =>
      prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
    );
  }, []);

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
      <header className="masthead">
        <button className="brand" onClick={goHome} title="Go to home">
          <span className="brand-mark">WL</span>
          <span className="brand-name">The Weinberg Theory Group Ledger</span>
        </button>
        <nav className="masthead-nav">
          {view === "search" && (
            <button className="nav-btn" onClick={() => setView("audit")}>
              View audit log
            </button>
          )}
          {currentUser && (
            <button
              className="nav-btn nav-btn--accent"
              onClick={() => setShowAddBook(true)}
            >
              Add book
            </button>
          )}
          {currentUser ? (
            <UserMenu
              user={currentUser}
              onLogout={handleLogout}
              onChangePassword={() => setShowChangePassword(true)}
              onOpenAdmin={() => setView("admin")}
            />
          ) : (
            <button className="nav-btn nav-btn--accent" onClick={() => setShowLogin(true)}>
              Log In
            </button>
          )}
        </nav>
      </header>
      <div className="masthead-rule" aria-hidden="true" />

      {view === "audit" ? (
        <AuditLog onBack={goHome} />
      ) : view === "signup" ? (
        <SignupView onBack={goHome} onRegistered={() => { goHome(); setShowLogin(true); }} />
      ) : view === "admin" ? (
        <UsersDashboard onBack={goHome} authToken={authToken} />
      ) : (
      <main className="console">
        <section className="hero">
          <p className="hero-eyebrow">Shared reference library · Weinberg theory group</p>
          <h1
            className="title clickable-title"
            onClick={goHome}
            title="Go to home"
          >
            Weinberg Theory Group Library Search
          </h1>
          <p className="hero-sub">
            Find who holds which volume — search the shelves by title, author, owner, or catalog number.
          </p>

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
              →
            </button>
          </div>

          <div className="search-fields" role="group" aria-label="Search in">
            <button
              type="button"
              className={`field-chip ${searchFields.length === 0 ? "active" : ""}`}
              onClick={() => setSearchFields([])}
            >
              All fields
            </button>
            {SEARCH_FIELDS.map((f) => (
              <button
                type="button"
                key={f.key}
                className={`field-chip ${searchFields.includes(f.key) ? "active" : ""}`}
                onClick={() => toggleSearchField(f.key)}
              >
                {f.label}
              </button>
            ))}
          </div>
        </section>

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
      </main>
      )}

      {selectedBook && (
        <BookModal
          book={selectedBook}
          onClose={() => setSelectedBook(null)}
          onFieldUpdate={handleFieldUpdate}
          onRemove={handleRemove}
          currentUser={currentUser}
          authToken={authToken}
        />
      )}

      {showAddBook && currentUser && (
        <AddBookModal
          onClose={() => setShowAddBook(false)}
          onAdded={handleAdded}
          authToken={authToken}
        />
      )}

      {showLogin && (
        <LoginModal
          onClose={() => setShowLogin(false)}
          onLogin={handleLogin}
          onSignupClick={() => { setShowLogin(false); setView("signup"); }}
        />
      )}

      {showChangePassword && (
        <ChangePasswordModal
          onClose={() => setShowChangePassword(false)}
          authToken={authToken}
        />
      )}

      <footer className="site-footer">
        {currentUser ? (
          <span>
            Editing as: <strong>{currentUser.first_name} {currentUser.last_name}</strong>
          </span>
        ) : <span />}
        <span>Your IP: {clientIp ?? "…"}</span>
      </footer>
    </div>
  );
}
