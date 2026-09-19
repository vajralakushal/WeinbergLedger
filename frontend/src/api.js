// Bearer-token auth header, spread into a fetch() headers object when a
// token is present. Kept as a pure function (token passed in explicitly)
// rather than reading localStorage directly, so components stay testable
// the same way they were with the old editorName prop.
export function authHeaders(token) {
  return token ? { Authorization: `Bearer ${token}` } : {};
}
