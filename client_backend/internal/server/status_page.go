package server

import (
	"html/template"
	"net/http"
	"strings"
)

// statusPage is the service page: three states, one template, no JavaScript.
//
// The page is NOT an interface. Its markup is fixed by nothing, has no version
// and changes freely; the machine-readable answer is GET /health and stays
// exactly what it was. This is said out loud in contract §1 for one reason: to
// stop anybody starting to parse it.
var statusPage = template.Must(template.New("status").Parse(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
{{if .Refresh}}<meta http-equiv="refresh" content="10">{{end}}
<title>NOX server</title>
<style>
:root { color-scheme: light dark; }
body { font: 16px/1.5 system-ui, sans-serif; margin: 0; padding: 2rem 1.5rem; max-width: 44rem; }
h1 { font-size: 1.4rem; margin: 0 0 .25rem; }
p.lead { margin: 0 0 2rem; opacity: .75; }
.qr { display: inline-block; padding: 1rem; background: #fff; border-radius: .5rem; }
code.link { display: block; margin: 1.25rem 0 0; padding: .75rem 1rem; border-radius: .5rem;
  background: rgba(127,127,127,.14); word-break: break-all; font-size: .95rem; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: .4rem 1.5rem; margin: 0; }
dt { opacity: .7; }
dd { margin: 0; font-variant-numeric: tabular-nums; }
.warn { margin: 1.5rem 0 0; padding: .75rem 1rem; border-radius: .5rem;
  background: rgba(200,120,0,.16); }
footer { margin-top: 2.5rem; font-size: .85rem; opacity: .6; }
</style></head><body>

{{if eq .State 0}}
<h1>Nobody has claimed this server yet</h1>
<p class="lead">Scan this from the NOX app on your phone, or paste the link below into it.
The first device to use it becomes the owner of this server.</p>
{{if .QR}}<div class="qr">{{.QR}}</div>{{else}}
<p class="warn">This machine has no address anything else can reach, so there is no code to scan.
Use the link printed when the server started.</p>{{end}}
{{if .Link}}<code class="link">{{.Link}}</code>{{end}}

{{else if eq .State 2}}
<h1>This server has no owner</h1>
<p class="lead">It holds people but nobody owns it, which no normal sequence of events produces.
Nobody can claim it in this state. The database has most likely been edited by hand.</p>

{{else}}
<h1>NOX server</h1>
<p class="lead">Running and claimed.</p>
{{end}}

{{if ne .State 0}}
<dl>
  <dt>Version</dt><dd>{{.Version}}</dd>
  <dt>Uptime</dt><dd>{{.Uptime}}</dd>
  <dt>Schema</dt><dd>v{{.Schema}}</dd>
  <dt>Storage id</dt><dd>{{.JournalID}}</dd>
  <dt>Database</dt><dd>{{.DBSize}}</dd>
  <dt>People</dt><dd>{{.People}}</dd>
  <dt>Devices</dt><dd>{{.Devices}}</dd>
  <dt>Chats</dt><dd>{{.Chats}}</dd>
  <dt>Messages</dt><dd>{{.Messages}}</dd>
</dl>
{{range .Warnings}}<p class="warn">{{.}}</p>{{end}}
{{end}}

<footer>This page is only reachable from this machine. It is for people, not for programs &mdash;
services should read /health instead.</footer>
</body></html>`))

// statusView is what the template sees. A flat struct on purpose: the template
// must not be able to reach anything that was not deliberately handed to it.
type statusView struct {
	State     int
	Refresh   bool
	QR        template.HTML
	Link      string
	Version   string
	Uptime    string
	Schema    int
	JournalID string
	DBSize    string
	People    int64
	Devices   int64
	Chats     int64
	Messages  int64
	Warnings  []string
}

// handleStatusPage serves the service page.
func (s *Server) handleStatusPage(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	status, err := s.collectStatus(r.Context())
	if err != nil {
		s.logger.Error("status page", "err", err)
		http.Error(w, "could not read the server's state", http.StatusInternalServerError)
		return
	}

	view := statusView{
		State: int(status.State),
		// Only the claimed page refreshes. Redrawing a QR under the camera
		// reading it breaks the one scenario this page exists for.
		Refresh:   status.State != stateNeedsClaim,
		Link:      status.Link,
		Version:   status.Version,
		Uptime:    humanDuration(status.Uptime),
		Schema:    status.Schema,
		JournalID: status.JournalID,
		DBSize:    humanBytes(status.DBBytes),
		People:    status.Counts.People,
		Devices:   status.Counts.Devices,
		Chats:     status.Counts.Chats,
		Messages:  status.Counts.Messages,
		Warnings:  status.Warnings,
	}
	if status.Link != "" {
		svg, err := qrSVG(status.Link, 6)
		if err != nil {
			// The link is still shown as text, which is the path that works
			// on a desktop with no camera anyway.
			s.logger.Error("render qr", "err", err)
		} else {
			view.QR = template.HTML(svg) //nolint:gosec // our own SVG, built from a link we generated
		}
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// The page carries a claim link. Nothing may keep a copy of it.
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	var out strings.Builder
	if err := statusPage.Execute(&out, view); err != nil {
		s.logger.Error("render status page", "err", err)
		http.Error(w, "could not render the page", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte(out.String()))
}

// StatusHandler is the service page's own mux, served on its own listener.
func (s *Server) StatusHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", s.handleStatusPage)
	return mux
}
