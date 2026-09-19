import { useState, useEffect } from "react";
import "./BookModal.css";
import "./AuthModal.css";

export default function LoginModal({ onClose, onLogin, onSignupClick }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError]       = useState(null);
  const [loading, setLoading]   = useState(false);

  useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    if (!username.trim() || !password) {
      setError("Enter your username and password.");
      return;
    }
    setLoading(true);
    try {
      const res = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: username.trim(), password }),
      });
      const data = await res.json();
      if (!data.ok) {
        setError(data.error ?? "Could not log in.");
        return;
      }
      onLogin(data.token, data.user);
    } catch {
      setError("Could not reach server.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay auth-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card auth-card">
        <h2 className="auth-title">Log In</h2>

        <form className="auth-form" onSubmit={submit}>
          <label className="add-book-field">
            <span className="add-book-label">Username</span>
            <input
              className="add-book-input"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoFocus
            />
          </label>
          <label className="add-book-field">
            <span className="add-book-label">Password</span>
            <input
              className="add-book-input"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>

          {error && <p className="status error">{error}</p>}

          <div className="add-book-actions">
            <button type="submit" className="add-book-submit" disabled={loading}>
              {loading ? "Logging in…" : "Log In"}
            </button>
            <button type="button" className="add-book-cancel" onClick={onClose}>Cancel</button>
          </div>
        </form>

        <p className="auth-switch">
          Don't have an account?{" "}
          <button type="button" className="auth-link" onClick={onSignupClick}>Sign Up</button>
        </p>
      </div>
    </div>
  );
}
