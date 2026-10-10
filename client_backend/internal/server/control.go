package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
)

// `noxd link` (046, FR-001): the terminal's way to the machine link, for a
// machine with no screen to open the service page on.
//
// The command does not open the database - only the running server does
// (invariant 1) - so it asks the server, over the service page's own loopback
// listener, with a request a page from another site cannot make:
//
//   - Host must name this machine - against a site rebound to 127.0.0.1 by DNS,
//     as on the page;
//   - X-Nox-Control: 1 must be present. A custom header makes a browser ask
//     first with a CORS preflight, and nothing here answers OPTIONS, so a
//     script on another site never gets as far as sending the request;
//   - Origin must be ABSENT. A browser sets it on every cross-origin request -
//     and on same-origin POSTs too - and a program like `noxd link` never does.
//
// Each failure is a 403 with nothing issued. The answer is the link itself, so
// the response is never stored anywhere on the way.
//
// The same road is what `noxd unlock` will take in 047.
const (
	controlLinkPath = "/control/link"
	controlHeader   = "X-Nox-Control"
	// maxControlReplyBytes bounds what the command reads back: a link and a
	// number fit many times over.
	maxControlReplyBytes = 16 << 10
)

// MachineLinkReply is what POST /control/link answers: the machine link and
// the moment it runs out, unix seconds.
type MachineLinkReply struct {
	Link      string `json:"link"`
	ExpiresAt int64  `json:"expires_at"`
}

// handleControlLink issues a machine link for `noxd link`. The previous live
// link stops working, the way it does for the page's button (SC-004), and the
// log says who asked - never the link (FR-005).
func (s *Server) handleControlLink(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if !localHost(r.Host) || r.Header.Get(controlHeader) != "1" || len(r.Header.Values("Origin")) > 0 {
		http.Error(w, "this answers the noxd link command on this machine, and nothing else", http.StatusForbidden)
		return
	}
	link, ml, err := s.issueMachineLink(r.Context(), "noxd link")
	if err != nil {
		s.logger.Error("issue machine link", "err", err)
		http.Error(w, "could not issue a link", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(MachineLinkReply{Link: link, ExpiresAt: ml.ExpiresAt}); err != nil {
		// The command hung up; it asks again, and the link it did not get is
		// voided by the next one.
		s.logger.Warn("answer noxd link", "err", err)
	}
}

// RequestMachineLink asks the server running on this machine for a new machine
// link, through its service page listener at statusAddr. It is the whole of
// `noxd link` but the printing.
func RequestMachineLink(ctx context.Context, statusAddr string) (MachineLinkReply, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://"+statusAddr+controlLinkPath, nil)
	if err != nil {
		return MachineLinkReply{}, fmt.Errorf("build the request: %w", err)
	}
	req.Header.Set(controlHeader, "1")
	// Straight to the loopback address, never through a proxy the environment
	// names: the request carries nothing secret, but its answer is a link.
	client := &http.Client{Transport: &http.Transport{Proxy: nil}}
	defer client.CloseIdleConnections()
	resp, err := client.Do(req)
	if err != nil {
		return MachineLinkReply{}, fmt.Errorf("no server answered on %s - is noxd running, and is that its -status-addr? (%w)", statusAddr, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxControlReplyBytes))
	if err != nil {
		return MachineLinkReply{}, fmt.Errorf("read the answer: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return MachineLinkReply{}, fmt.Errorf("the server at %s refused: %s", statusAddr, resp.Status)
	}
	var got MachineLinkReply
	if err := json.Unmarshal(body, &got); err != nil {
		return MachineLinkReply{}, fmt.Errorf("the server at %s answered something else: %w", statusAddr, err)
	}
	if _, err := ParsePairingLink(got.Link); err != nil {
		return MachineLinkReply{}, fmt.Errorf("the server at %s answered a link that does not read: %w", statusAddr, err)
	}
	return got, nil
}

// LinkReachesOnlyThisMachine reports whether every address a link names is
// this machine's own loopback - a link only the app running here can follow.
// `noxd link -qr` draws no code for one, the way the page draws none: a code a
// phone cannot follow is worse than none, because the person scans it and gets
// a network error instead of being told what to change.
//
// Names other than localhost are taken as reachable without resolving them: a
// code wrongly withheld costs more than one drawn for a name that turns out to
// be local, and the link is printed under it either way.
func LinkReachesOnlyThisMachine(link string) bool {
	parsed, err := ParsePairingLink(link)
	if err != nil || parsed.Onion != nil {
		return false
	}
	for _, addr := range parsed.Direct {
		host, _, err := net.SplitHostPort(addr)
		if err != nil {
			return false
		}
		if strings.EqualFold(strings.TrimSuffix(host, "."), "localhost") {
			continue
		}
		if ip := net.ParseIP(host); ip == nil || !ip.IsLoopback() {
			return false
		}
	}
	return len(parsed.Direct) > 0
}
