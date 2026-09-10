package server

import (
	"html/template"
	"net"
	"net/http"
	"strings"
)

// statusPage is the service page: two states, one template, no JavaScript.
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
{{if .Owned}}
<h1>Your server is waiting for you</h1>
<p class="lead">It has an owner but no device left to reach it with &mdash; signing out on the last one
does this. Scan this from the NOX app, or paste the link below into it, and you are back in with your
chats and messages.</p>
{{else if .HasPerson}}
<h1>This server holds a conversation</h1>
<p class="lead">It records no owner, which no normal sequence of events produces &mdash; a restore or a
hand edit most likely. Scan this from the NOX app, or paste the link below into it: the device that
presents it signs in as the person this server already belongs to, with their chats and messages.</p>
{{else}}
<h1>Nobody has claimed this server yet</h1>
<p class="lead">Scan this from the NOX app on your phone, or paste the link below into it.
The first device to use it becomes the owner of this server.</p>
{{end}}
{{if .QR}}<div class="qr">{{.QR}}</div>{{else}}
<p class="warn">This server is reachable from this machine only, so there is no code for a phone to
scan &mdash; but the link below works in the NOX app running here. To claim it from a phone instead,
start the server with <code>-addr</code> set to an address on your network.</p>{{end}}
{{if .Link}}<code class="link">{{.Link}}</code>{{end}}

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
  <dt>Devices</dt><dd>{{.Devices}}</dd>
  <dt>Chats</dt><dd>{{.Chats}}</dd>
  <dt>Messages</dt><dd>{{.Messages}}</dd>
</dl>
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
	Devices   int64
	Chats     int64
	Messages  int64
	Owned     bool
	HasPerson bool
}

// handleStatusPage serves the service page.
func (s *Server) handleStatusPage(w http.ResponseWriter, r *http.Request) {
	// The listener keeps the network out; this keeps the operator's own browser
	// out. Without it a page on any site can be rebound to 127.0.0.1 by DNS,
	// fetch this one as same-origin and read the claim link straight off it -
	// after which the machine belongs to whoever served that page. A loopback
	// socket does not help, because the request really does come from loopback.
	if !localHost(r.Host) {
		http.Error(w, "this page is only served to this machine", http.StatusForbidden)
		return
	}
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
		Devices:   status.Counts.Devices,
		Chats:     status.Counts.Chats,
		Messages:  status.Counts.Messages,
		Owned:     status.Owned,
		HasPerson: status.HasPerson,
	}
	// The code is drawn only when something other than this machine could dial
	// the address in it. The LINK is shown either way: pasting it into the app
	// on this machine is how a loopback-bound server is claimed.
	if status.Link != "" && status.Scannable {
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
	// The page carries a claim link. Nothing may keep a copy of it, embed it in
	// another page, or guess at its type.
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-ancestors 'none'")
	var out strings.Builder
	if err := statusPage.Execute(&out, view); err != nil {
		s.logger.Error("render status page", "err", err)
		http.Error(w, "could not render the page", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte(out.String()))
}

// localHost reports whether a Host header names this machine.
//
// Names as well as literals, because a browser sends whatever was typed: a
// person opens http://localhost:8081 as readily as the address. What is
// refused is a name that merely RESOLVES here - that is the rebinding attack,
// and the whole point is that resolution is not to be trusted.
func localHost(host string) bool {
	name, _, err := net.SplitHostPort(host)
	if err != nil {
		// No port: the header is the bare host.
		name = host
	}
	name = strings.TrimSuffix(strings.TrimPrefix(name, "["), "]")
	// A browser sends "localhost." for a URL typed with the root dot. Same host,
	// and refusing it is an unexplainable no.
	name = strings.TrimSuffix(name, ".")
	if strings.EqualFold(name, "localhost") {
		return true
	}
	ip := net.ParseIP(name)
	return ip != nil && ip.IsLoopback()
}

// StatusHandler is the service page's own mux, served on its own listener.
func (s *Server) StatusHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", s.handleStatusPage)
	return mux
}
