// Returns the editor's name, prompting for it if not already set.
// Returns "" if the user cancels or leaves it blank (caller should abort).
export function ensureEditorName(editorName, onEditorNameChange) {
  if (editorName) return editorName;
  const entered = window.prompt(
    "Enter your name (recorded for the audit trail):",
    ""
  );
  const name = entered?.trim() ?? "";
  if (name) onEditorNameChange(name);
  return name;
}
