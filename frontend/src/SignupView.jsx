import { useState } from "react";
import "./AddBookModal.css";
import "./SignupView.css";

const EMPTY = { first_name: "", last_name: "", username: "", password: "", light_speed: "" };

export default function SignupView({ onBack, onRegistered }) {
  const [values, setValues]       = useState(EMPTY);
  const [denied, setDenied]       = useState(false);
  const [error, setError]         = useState(null);
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const setField = (key, v) => setValues((prev) => ({ ...prev, [key]: v }));

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    setDenied(false);

    if (!values.first_name.trim() || !values.last_name.trim() || !values.username.trim() || !values.password) {
      setError("First name, last name, username, and password are all required.");
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch("/api/registrations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(values),
      });
      const data = await res.json();
      if (data.denied) {
        setDenied(true);
        return;
      }
      if (!data.ok) {
        setError(data.error ?? "Could not submit registration.");
        return;
      }
      setSubmitted(true);
    } catch {
      setError("Could not reach server.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="signup-card">
      <div className="signup-header">
        <button className="audit-back" onClick={onBack}>← Back to search</button>
        <h1 className="title">Sign Up</h1>
      </div>

      {submitted ? (
        <div className="signup-success">
          <p className="add-book-success">
            Your registration has been submitted. An admin will review it before you can log in.
          </p>
          <button className="add-book-submit" onClick={onRegistered}>Back to Log In</button>
        </div>
      ) : (
        <>
          {denied && <p className="status error signup-denied">Registration has been denied.</p>}

          <form className="signup-form" onSubmit={submit}>
            <label className="add-book-field">
              <span className="add-book-label">First Name</span>
              <input
                className="add-book-input"
                value={values.first_name}
                onChange={(e) => setField("first_name", e.target.value)}
                autoFocus
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">Last Name</span>
              <input
                className="add-book-input"
                value={values.last_name}
                onChange={(e) => setField("last_name", e.target.value)}
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">Username</span>
              <input
                className="add-book-input"
                value={values.username}
                onChange={(e) => setField("username", e.target.value)}
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">Password</span>
              <input
                className="add-book-input"
                type="password"
                value={values.password}
                onChange={(e) => setField("password", e.target.value)}
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">What is the speed of light (in God-given units)?</span>
              <input
                className="add-book-input"
                value={values.light_speed}
                onChange={(e) => setField("light_speed", e.target.value)}
              />
            </label>

            {error && <p className="status error">{error}</p>}

            <div className="add-book-actions">
              <button type="submit" className="add-book-submit" disabled={submitting}>
                {submitting ? "Submitting…" : "Submit Registration"}
              </button>
            </div>
          </form>
        </>
      )}
    </div>
  );
}
