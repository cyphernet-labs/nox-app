package server

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"html/template"
	"net"
	"net/http"
	"strings"

	"nox.app/client-backend/internal/store"
)

// maxAddressFormBytes bounds the body of POST /addresses: a token, a kind and
// one address fit many times over.
const maxAddressFormBytes = 4096

// statusPage is the service page: two states, one template, and exactly one
// script - see copyScript for what it is allowed to be and why.
//
// The page is NOT an interface. Its markup is fixed by nothing, has no version
// and changes freely; the machine-readable answer is GET /health beside it and
// stays exactly what it was. This is said out loud in contract §1 for one
// reason: to stop anybody starting to parse it.
//
// Neither state refreshes itself any more (045). Both carry the address forms,
// and a page that reloads every few seconds wipes an address halfway through
// being pasted; the numbers on the claimed page are as current as the moment
// it was opened, and a reload brings them up to date.
var statusPage = template.Must(template.New("status").Parse(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOX server</title>
<style>
:root { color-scheme: light dark; }
body { font: 16px/1.5 system-ui, sans-serif; margin: 0; padding: 2rem 1.5rem; max-width: 44rem; }
h1 { font-size: 1.4rem; margin: 0 0 .25rem; }
p.lead { margin: 0 0 2rem; opacity: .75; }
.qr { display: inline-block; padding: 1rem; background: #fff; border-radius: .5rem; }
code.link { display: block; margin: 1.25rem 0 0; padding: .75rem 1rem; border-radius: .5rem;
  background: rgba(127,127,127,.14); word-break: break-all; font-size: .95rem; }
.copyrow { display: flex; align-items: center; gap: .75rem; margin: .6rem 0 0; }
button.copy, button.set { font: inherit; font-size: .9rem; padding: .4rem .9rem; border-radius: .4rem;
  border: 1px solid rgba(127,127,127,.4); background: rgba(127,127,127,.1);
  color: inherit; cursor: pointer; }
button.copy:hover, button.set:hover { background: rgba(127,127,127,.22); }
.copied { font-size: .85rem; opacity: .75; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: .4rem 1.5rem; margin: 0; }
dt { opacity: .7; }
dd { margin: 0; font-variant-numeric: tabular-nums; }
.warn { margin: 1.5rem 0 0; padding: .75rem 1rem; border-radius: .5rem;
  background: rgba(200,120,0,.16); }
footer { margin-top: 2.5rem; font-size: .85rem; opacity: .6; }
h2 { font-size: 1.1rem; margin: 2rem 0 .5rem; }
p.found { margin: 0; opacity: .7; }
ul.found { margin: .3rem 0 0; padding-left: 1.25rem; }
form.addr { margin: 1.25rem 0 0; }
form.addr label { display: block; margin: 0 0 .35rem; opacity: .7; }
.addrrow { display: flex; gap: .6rem; }
.addrrow input { flex: 1; min-width: 0; font: inherit; font-size: .95rem; padding: .4rem .7rem;
  border-radius: .4rem; border: 1px solid rgba(127,127,127,.4); background: transparent; color: inherit; }
p.note { margin: .6rem 0 0; padding: .5rem .8rem; border-radius: .4rem; font-size: .9rem; }
p.saved { background: rgba(0,150,90,.16); }
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
{{if .Link}}<code class="link">{{.Link}}</code>
<p class="copyrow"><button type="button" class="copy" hidden>Copy link</button>
<span class="copied" role="status"></span></p>{{end}}

{{else}}
<h1>NOX server</h1>
{{if .Owned}}<p class="lead">Running and claimed.</p>
{{else}}<p class="lead">Running. Your devices reach it normally.</p>
<p class="warn">This server records no owner, which no normal sequence of events produces &mdash; a
restore or a hand edit most likely. Nothing is broken: the devices already paired keep working. The
marker is written back the next time the machine is claimed, which needs every device signed out
first.</p>{{end}}
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

<h2>Addresses</h2>
<p class="found">Found on this machine's networks</p>
{{if .Found}}<ul class="found">{{range .Found}}<li><code>{{.}}</code></li>{{end}}</ul>{{else}}<p>&mdash;</p>{{end}}
{{range .Forms}}
<form class="addr" method="post" action="/addresses">
<label for="addr-{{.Kind}}">{{.Label}}</label>
<div class="addrrow">
<input id="addr-{{.Kind}}" name="value" value="{{.Value}}" autocomplete="off" autocapitalize="off" spellcheck="false">
<button type="submit" class="set">Set</button>
</div>
<input type="hidden" name="kind" value="{{.Kind}}">
<input type="hidden" name="token" value="{{$.FormToken}}">
{{- with .Saved}}
<p class="note saved" role="status">{{.}}</p>
{{- end}}
{{- with .Invalid}}
<p class="note warn" role="alert">{{.}}</p>
{{- end}}
{{- with .Warning}}
<p class="note warn">{{.}}</p>
{{- end}}
</form>
{{end}}

<footer>This page is only reachable from this machine. It is for people, not for programs &mdash;
services should read /health instead.</footer>
{{if .Link}}<script>{{.CopyScript}}</script>{{end}}
</body></html>`))

// copyScript is the page's only JavaScript, and it exists for one gesture:
// putting the claim link on the clipboard so nobody has to select two lines of
// base64 by hand.
//
// Three things make it safe to have here at all:
//
//   - The button starts HIDDEN and this script reveals it. If the script does
//     not run - a stricter policy, scripting off - the page is what it was
//     rather than a control that does nothing when pressed.
//   - The policy admits it by HASH, not by 'unsafe-inline'. Exactly these bytes
//     may run and nothing else, so an injection has no opening even if one
//     were ever found.
//   - `connect-src` stays at the default-src 'none'. The script can read the
//     link, which is the point; it has nowhere on earth to send it.
//
// The link is read out of the DOM rather than templated in, so it never has to
// survive a second round of escaping.
//
// Clipboard access needs a secure context. `http://127.0.0.1` and
// `http://localhost` are potentially trustworthy origins, so this page has one
// without TLS - measured in a browser, not assumed. The fallback is still
// real: selecting the text leaves the person one keystroke away.
const copyScript = `(function () {
  var link = document.querySelector('code.link');
  var button = document.querySelector('button.copy');
  var said = document.querySelector('.copied');
  if (!link || !button || !said) { return; }
  button.hidden = false;
  var mac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
  var byHand = mac ? 'Selected - press Cmd+C' : 'Selected - press Ctrl+C';
  var timer;
  function say(text) {
    said.textContent = text;
    clearTimeout(timer);
    timer = setTimeout(function () { said.textContent = ''; }, 4000);
  }
  function select() {
    var range = document.createRange();
    range.selectNodeContents(link);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }
  button.addEventListener('click', function () {
    if (!navigator.clipboard) { select(); say(byHand); return; }
    navigator.clipboard.writeText(link.textContent.trim()).then(
      function () { say('Copied'); },
      function () { select(); say(byHand); }
    );
  });
})();`

// contentSecurityPolicy is the page's policy, and it is built rather than
// written down so the script and the hash that admits it cannot drift apart.
//
// Derived on every response from the one copy of the script: a hash written
// down beside it would be a second copy of one fact, and two copies eventually
// disagree. Hashing six hundred bytes costs nothing on a page a person opens
// by hand.
//
// A page with no link carries no script, and then says so - `script-src` is
// absent entirely and `default-src 'none'` forbids the lot.
//
// `form-action 'self'` is spelled out because `default-src` does not cover it:
// the address forms may post here and nowhere else.
func contentSecurityPolicy(withScript bool) string {
	policy := "default-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-ancestors 'none'; form-action 'self'"
	if !withScript {
		return policy
	}
	sum := sha256.Sum256([]byte(copyScript))
	return policy + "; script-src 'sha256-" + base64.StdEncoding.EncodeToString(sum[:]) + "'"
}

// statusView is what the template sees. A flat struct on purpose: the template
// must not be able to reach anything that was not deliberately handed to it.
type statusView struct {
	State int
	QR    template.HTML
	Link  string
	// CopyScript is the script below the page, typed so the escaper leaves it
	// alone. Emitted only with a link, because that is the only thing it acts on.
	CopyScript template.JS
	Version    string
	Uptime     string
	Schema     int
	JournalID  string
	DBSize     string
	Devices    int64
	Chats      int64
	Messages   int64
	Owned      bool
	HasPerson  bool
	// Found are the addresses the machine finds on its networks; Forms are the
	// two it stores, each with its Set; FormToken is what both forms carry.
	Found     []string
	Forms     []addressForm
	FormToken string
}

// addressForm is one stored address on the page: its field, and what the page
// has to say about it - the outcome of the last Set, and a start parameter
// that was not applied.
type addressForm struct {
	Kind    string
	Label   string
	Value   string
	Saved   string
	Invalid string
	Warning string
}

// addressForms words the stored addresses for a person (contract
// service-page-addresses). saved and invalid are the kinds the redirect after a
// Set named; anything else in them is ignored. The values themselves never
// travel in that redirect, so a URL in a browser's history names no address.
func addressForms(stored store.Addresses, warnings []addressWarning, saved, invalid string) []addressForm {
	forms := make([]addressForm, 0, 2)
	for _, kind := range []store.AddressKind{store.AddressPublic, store.AddressOnion} {
		f := addressForm{Kind: string(kind), Value: stored.Value(kind)}
		f.Label = "Public address"
		if kind == store.AddressOnion {
			f.Label = "Onion address"
		}
		if saved == string(kind) {
			// Read back rather than carried in the redirect: an empty field is
			// a deletion, and "carry it" would be the wrong thing to say.
			f.Saved = "Saved. New links carry it, and connected devices get it now."
			if f.Value == "" {
				f.Saved = "Removed. New links no longer carry it, and connected devices learn it now."
			}
		}
		if invalid == string(kind) {
			f.Invalid = "That isn't a valid address. Use host:port, like nox.example.org:8443. Nothing was changed."
			if kind == store.AddressOnion {
				f.Invalid = "That isn't a valid onion address. Nothing was changed."
			}
		}
		for _, w := range warnings {
			if w.Kind == kind {
				f.Warning = parameterWarning(kind, f.Value)
			}
		}
		forms = append(forms, f)
	}
	return forms
}

// parameterWarning says a start parameter was not applied and what the server
// runs with instead - the address it holds NOW, so an address set on this page
// since the start is what the warning names.
func parameterWarning(kind store.AddressKind, current string) string {
	if kind == store.AddressOnion {
		if current == "" {
			current = "no onion address"
		}
		return paramFlag(kind) + " is not a valid onion address. The server keeps " + current + "."
	}
	if current == "" {
		current = "no public address"
	}
	return paramFlag(kind) + " is not a valid address. The server keeps " + current + "."
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

	query := r.URL.Query()
	view := statusView{
		State:      int(status.State),
		Link:       status.Link,
		CopyScript: template.JS(copyScript), //nolint:gosec // our own constant, admitted by its hash
		Version:    status.Version,
		Uptime:     humanDuration(status.Uptime),
		Schema:     status.Schema,
		JournalID:  status.JournalID,
		DBSize:     humanBytes(status.DBBytes),
		Devices:    status.Counts.Devices,
		Chats:      status.Counts.Chats,
		Messages:   status.Counts.Messages,
		Owned:      status.Owned,
		HasPerson:  status.HasPerson,
		Found:      status.Found,
		Forms:      addressForms(status.Stored, s.addrWarnings, query.Get("saved"), query.Get("invalid")),
		FormToken:  s.formToken,
	}
	// The code is drawn only when something other than this machine could dial
	// an address in it. The LINK is shown either way: pasting it into the app
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

	pageHeaders(w)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", contentSecurityPolicy(view.Link != ""))
	var out strings.Builder
	if err := statusPage.Execute(&out, view); err != nil {
		s.logger.Error("render status page", "err", err)
		http.Error(w, "could not render the page", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte(out.String()))
}

// pageHeaders are the headers every answer of the page carries. The page holds
// a claim link and the form token: nothing may keep a copy of it, embed it in
// another page, or guess at its type.
//
// The referrer policy is same-origin and NOT no-referrer, and that is
// load-bearing for the forms. Under no-referrer a browser sends `Origin: null`
// on a form's POST (Fetch, "append a request Origin header"), and the Origin
// check below would refuse every honest Set. same-origin hands a referrer to
// this page alone - which has nothing to learn from it - and to no other site.
func pageHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "same-origin")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("X-Content-Type-Options", "nosniff")
}

// handleSetAddress is the page's Set (045, FR-004): it writes one stored
// address, and the address reaches new links at once and greeted devices
// within moments.
//
// Only the page's own form may write, and three checks decide that, in this
// order, each answered 403 without a word about the others:
//
//   - Host names this machine - the same check as the page, against a site
//     rebound to 127.0.0.1 by DNS;
//   - Origin is present and is this page's own - a form on another site,
//     opened in a browser on this machine, posts here with ITS origin, and the
//     loopback socket cannot tell;
//   - the form token matches this process's, compared in constant time - the
//     one thing a page from elsewhere cannot read off this one.
//
// Only then is the form believed: an unknown kind is a 400, an address that
// does not check out sends the person back with nothing written, and an empty
// value deletes. The redirect names the kind and never the value.
func (s *Server) handleSetAddress(w http.ResponseWriter, r *http.Request) {
	pageHeaders(w)
	if !localHost(r.Host) {
		http.Error(w, "this page is only served to this machine", http.StatusForbidden)
		return
	}
	// Compared without regard to case, like the host names in it; a browser
	// writes both in lower case anyway.
	if origin := r.Header.Get("Origin"); origin == "" || !strings.EqualFold(origin, "http://"+r.Host) {
		http.Error(w, "this form is only accepted from this page", http.StatusForbidden)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxAddressFormBytes)
	// The body only: a token in the URL would be one a link can carry.
	// A body that cannot be read has no token in it.
	if err := r.ParseForm(); err != nil || !s.formTokenMatches(r.PostForm.Get("token")) {
		http.Error(w, "this form is only accepted from this page", http.StatusForbidden)
		return
	}
	kind := store.AddressKind(r.PostForm.Get("kind"))
	if kind != store.AddressPublic && kind != store.AddressOnion {
		http.Error(w, "unknown address kind", http.StatusBadRequest)
		return
	}
	value, err := normalizeAddress(kind, strings.TrimSpace(r.PostForm.Get("value")))
	if err != nil {
		http.Redirect(w, r, "/?invalid="+string(kind), http.StatusSeeOther)
		return
	}
	if err := s.store.SetAddress(r.Context(), kind, value); err != nil {
		s.logger.Error("set address", "kind", kind, "err", err)
		http.Error(w, "could not save the address", http.StatusInternalServerError)
		return
	}
	// The kind and whether it was cleared - never the value: an onion address
	// does not reach the log (FR-022), and the public one has no reason to.
	s.logger.Info("address set on the service page", "kind", kind, "cleared", value == "")
	// The watcher reads the new address and tells every greeted connection.
	s.pokeAddresses()
	http.Redirect(w, r, "/?saved="+string(kind), http.StatusSeeOther)
}

// formTokenMatches compares a posted token with this process's in constant
// time. An empty one never matches, not even an empty expected one: a Server
// built without a token must refuse every form rather than accept every one.
func (s *Server) formTokenMatches(got string) bool {
	if s.formToken == "" || got == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.formToken)) == 1
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

// StatusHandler is the service page's own mux, served on its own listener,
// and the home of /health since 044 and of the address forms since 045.
//
// /health moved here because the main port answers nothing before the channel
// check, and a service manager or a tunnel probing liveness proves no device
// key. The answer is the one it always was; no Host check, because it says
// nothing a rebound page could use.
func (s *Server) StatusHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /", s.handleStatusPage)
	mux.HandleFunc("POST /addresses", s.handleSetAddress)
	return mux
}
