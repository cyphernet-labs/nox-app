package server

import (
	"html/template"
	"net/http"
	"strings"
)

// lockPage is the service page while the server waits for its password
// (047): the first password with its repeat on a fresh server, the password
// alone on a locked one. Nothing else - no link, no address, no figure about
// the server: whoever opens the page of a locked server learns that it is
// locked, and that is all. No script either, and the policy admits none.
var lockPage = template.Must(template.New("lock").Parse(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOX server</title>
<style>
:root { color-scheme: light dark; }
body { font: 16px/1.5 system-ui, sans-serif; margin: 0; padding: 2rem 1.5rem; max-width: 30rem; }
h1 { font-size: 1.4rem; margin: 0 0 1.5rem; }
label { display: block; margin: 1rem 0 .35rem; opacity: .7; }
input { box-sizing: border-box; width: 100%; font: inherit; font-size: .95rem; padding: .4rem .7rem;
  border-radius: .4rem; border: 1px solid rgba(127,127,127,.4); background: transparent; color: inherit; }
button { margin: 1.25rem 0 0; font: inherit; font-size: .9rem; padding: .4rem .9rem; border-radius: .4rem;
  border: 1px solid rgba(127,127,127,.4); background: rgba(127,127,127,.1); color: inherit; cursor: pointer; }
button:hover { background: rgba(127,127,127,.22); }
p.note { margin: 1rem 0 0; padding: .5rem .8rem; border-radius: .4rem; font-size: .9rem; }
.warn { background: rgba(200,120,0,.16); }
footer { margin-top: 2.5rem; font-size: .85rem; opacity: .6; }
</style></head><body>
{{if .Setup}}
<h1>Set a password for this server</h1>
<form method="post" action="/password/setup">
<label for="password">Password</label>
<input id="password" type="password" name="password" autocomplete="new-password" required autofocus>
<label for="repeat">Repeat password</label>
<input id="repeat" type="password" name="repeat" autocomplete="new-password" required>
<input type="hidden" name="token" value="{{.FormToken}}">
{{with .Error}}<p class="note warn" role="alert">{{.}}</p>{{end}}
<p class="note warn">If you forget this password, the server's data can't be opened by anyone, including you.</p>
<button type="submit">Set password</button>
</form>
{{else}}
<h1>This server is locked</h1>
<form method="post" action="/password/unlock">
<label for="password">Password</label>
<input id="password" type="password" name="password" autocomplete="current-password" required autofocus>
<input type="hidden" name="token" value="{{.FormToken}}">
{{with .Error}}<p class="note warn" role="alert">{{.}}</p>{{end}}
<button type="submit">Unlock</button>
</form>
{{end}}
<footer>This page is only reachable from this machine.</footer>
</body></html>`))

// lockView is what the lock page's template sees: whether it is the first
// password, what went wrong with the last attempt, and the form token.
type lockView struct {
	Setup     bool
	Error     string
	FormToken string
}

// passwordMessage words an error code from the redirect after a password
// form (contracts/control-and-page.md). Anything else in the query says
// nothing: the page never repeats what a URL put there.
func passwordMessage(code string) string {
	switch code {
	case codeWrong:
		return "Wrong password."
	case codeShort:
		return "Use at least 12 characters."
	case codeMismatch:
		return "The passwords don't match."
	default:
		return ""
	}
}

// handleLockPage serves the page of a server that is not open yet.
func (g *gate) handleLockPage(w http.ResponseWriter, r *http.Request) {
	view := lockView{
		Setup:     g.current() == stateSetup,
		Error:     passwordMessage(r.URL.Query().Get("error")),
		FormToken: g.formToken,
	}
	pageHeaders(w)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", contentSecurityPolicy(false))
	var out strings.Builder
	if err := lockPage.Execute(&out, view); err != nil {
		g.logger.Error("render the lock page", "err", err)
		http.Error(w, "could not render the page", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte(out.String()))
}
