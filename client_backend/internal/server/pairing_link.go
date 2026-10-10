package server

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"unicode/utf8"

	"nox.app/client-backend/internal/store"
)

// Pairing link format, version 3 (contract §8A, feature 044):
//
//	nox://pair/<base64url, no padding>
//	version (1) ‖ server key (32) ‖ token (16) ‖ addresses
//	address = type (1) ‖ length of the value (1) ‖ value
//
// One shape for every case - machine link and invite alike - so there is one builder,
// one parser and one set of shared vectors (testdata/link-vectors.json, a
// copy of the contract's). The server KEY travels whole, not a fingerprint: it
// is Ed25519's thirty-two bytes, and it is what the device checks the channel
// against before it sends a single command.
const (
	pairingLinkVersion = 3
	pairingLinkPrefix  = "nox://pair/"

	// The address types. An unknown type is skipped by its length, which is
	// what lets a later version add one without breaking this parser.
	addrTypeIPv4  = 1
	addrTypeIPv6  = 2
	addrTypeName  = 3
	addrTypeOnion = 4

	// linkHeaderSize is version, key and token: the least a link can be.
	linkHeaderSize = 1 + ed25519.PublicKeySize + 16
	// maxLinkNameBytes is the longest host name a link carries - DNS's own
	// limit, and what a one-byte length leaves room for beside the port.
	maxLinkNameBytes = 253
)

// The two refusals of the parse rules. They are told apart because the person
// does different things about them: a malformed link is retyped or rescanned,
// a newer one means updating the app.
var (
	ErrLinkMalformed    = errors.New("the pairing link is malformed")
	ErrLinkNewerVersion = errors.New("the pairing link is newer than this program")
)

// PairingLink is a version-3 link read back: what cmd/smoke needs to reach a
// server, and what the tests compare with the shared vectors.
type PairingLink struct {
	ServerKey ed25519.PublicKey
	// Token is the token as `pair` carries it: base64url without padding.
	Token string
	// Direct are the direct addresses as host:port, in the link's order: the
	// public address first when the link carries one (045). The format does
	// not tell the two apart and does not need to - a device tries them in
	// order, and shows the first in its "server address" field.
	Direct []string
	// Onion is the onion service's public key, nil when the link names none.
	// A link that names several keeps the first.
	Onion ed25519.PublicKey
}

// BuildPairingLink renders the link a person carries to an app: the server's
// key, the token, the direct addresses in order and then, when onion is not
// nil, the onion service.
//
// It refuses to render what the parse rules would refuse to read - no
// address, a port of 0, a name that is empty, too long or not UTF-8 - so a
// server never prints a link no device can use.
func BuildPairingLink(serverKey ed25519.PublicKey, token string, direct []string, onion ed25519.PublicKey) (string, error) {
	if len(serverKey) != ed25519.PublicKeySize {
		return "", fmt.Errorf("server key is %d bytes, want %d", len(serverKey), ed25519.PublicKeySize)
	}
	tok, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(tok) != 16 {
		return "", errors.New("token is not 16 bytes of base64url")
	}
	if len(direct) == 0 && onion == nil {
		return "", errors.New("a link needs at least one address")
	}

	payload := make([]byte, 0, linkHeaderSize+20*len(direct)+34)
	payload = append(payload, pairingLinkVersion)
	payload = append(payload, serverKey...)
	payload = append(payload, tok...)
	for _, addr := range direct {
		if payload, err = appendDirectAddress(payload, addr); err != nil {
			return "", err
		}
	}
	if onion != nil {
		if len(onion) != ed25519.PublicKeySize {
			return "", fmt.Errorf("onion service key is %d bytes, want %d", len(onion), ed25519.PublicKeySize)
		}
		payload = append(payload, addrTypeOnion, ed25519.PublicKeySize)
		payload = append(payload, onion...)
	}
	return pairingLinkPrefix + base64.RawURLEncoding.EncodeToString(payload), nil
}

// appendDirectAddress encodes host:port by what the host IS, written
// explicitly rather than left for the parser to infer: "1.2.3.4" reads as an
// address and as a name alike, and one byte settles that for good.
func appendDirectAddress(payload []byte, addr string) ([]byte, error) {
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, fmt.Errorf("split pairing address: %w", err)
	}
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil || port == 0 {
		return nil, fmt.Errorf("pairing address %q has no usable port", addr)
	}
	switch ip := net.ParseIP(host); {
	case ip != nil && ip.To4() != nil:
		payload = append(payload, addrTypeIPv4, 4+2)
		payload = append(payload, ip.To4()...)
	case ip != nil:
		payload = append(payload, addrTypeIPv6, 16+2)
		payload = append(payload, ip.To16()...)
	default:
		// A colon is an IPv6 literal net.ParseIP could not read - one with a
		// zone, say - and as a name it would dial nothing at all.
		if host == "" || len(host) > maxLinkNameBytes || !utf8.ValidString(host) || strings.Contains(host, ":") {
			return nil, fmt.Errorf("host %q does not fit a pairing link", host)
		}
		payload = append(payload, addrTypeName, byte(len(host)+2))
		payload = append(payload, host...)
	}
	return binary.BigEndian.AppendUint16(payload, uint16(port)), nil
}

// ParsePairingLink reads a link by the contract's parse rules, in their
// order: prefix and base64url, the least length, the version, the addresses
// one by one, and at least one address the parser knows.
func ParsePairingLink(link string) (PairingLink, error) {
	rest, ok := strings.CutPrefix(strings.TrimSpace(link), pairingLinkPrefix)
	if !ok {
		return PairingLink{}, ErrLinkMalformed
	}
	payload, err := base64.RawURLEncoding.DecodeString(rest)
	if err != nil || len(payload) < linkHeaderSize {
		return PairingLink{}, ErrLinkMalformed
	}
	switch version := payload[0]; {
	case version > pairingLinkVersion:
		return PairingLink{}, ErrLinkNewerVersion
	case version != pairingLinkVersion:
		return PairingLink{}, ErrLinkMalformed
	}
	out := PairingLink{
		ServerKey: ed25519.PublicKey(payload[1 : 1+ed25519.PublicKeySize]),
		Token:     base64.RawURLEncoding.EncodeToString(payload[1+ed25519.PublicKeySize : linkHeaderSize]),
	}
	known := 0
	for at := linkHeaderSize; at < len(payload); {
		if len(payload)-at < 2 {
			return PairingLink{}, ErrLinkMalformed
		}
		kind, size := payload[at], int(payload[at+1])
		at += 2
		if len(payload)-at < size {
			return PairingLink{}, ErrLinkMalformed
		}
		value := payload[at : at+size]
		at += size
		switch kind {
		case addrTypeIPv4, addrTypeIPv6, addrTypeName:
			addr, err := parseDirectAddress(kind, value)
			if err != nil {
				return PairingLink{}, err
			}
			out.Direct = append(out.Direct, addr)
		case addrTypeOnion:
			if size != ed25519.PublicKeySize {
				return PairingLink{}, ErrLinkMalformed
			}
			if out.Onion == nil {
				out.Onion = ed25519.PublicKey(value)
			}
		default:
			// Unknown: skipped by its length, never guessed at.
			continue
		}
		known++
	}
	if known == 0 {
		return PairingLink{}, ErrLinkMalformed
	}
	return out, nil
}

// parseDirectAddress reads one IPv4, IPv6 or name value back into host:port.
func parseDirectAddress(kind byte, value []byte) (string, error) {
	var host string
	switch kind {
	case addrTypeIPv4:
		if len(value) != 4+2 {
			return "", ErrLinkMalformed
		}
		host = net.IP(value[:4]).String()
	case addrTypeIPv6:
		if len(value) != 16+2 {
			return "", ErrLinkMalformed
		}
		host = net.IP(value[:16]).String()
	default:
		if len(value) < 1+2 || !utf8.Valid(value[:len(value)-2]) {
			return "", ErrLinkMalformed
		}
		host = string(value[:len(value)-2])
	}
	port := binary.BigEndian.Uint16(value[len(value)-2:])
	if port == 0 {
		return "", ErrLinkMalformed
	}
	return net.JoinHostPort(host, strconv.Itoa(int(port))), nil
}

// linkCarries says which of the stored addresses a link names: what the
// device.invite reply reports, and what decides whether a code is worth
// drawing for a phone.
type linkCarries struct {
	Public bool
	Onion  bool
}

// buildLink is the link every issuer hands out (044, 045, 046) - the machine
// link on the service page and from `noxd link`, and the device invite alike:
// the public address first when one is set, then the one direct address, then
// the onion service when one is set.
//
// The public address leads because it is what the app shows in its "server
// address" field - the first direct address of the link - and the one that
// works from anywhere the onion path is not wanted. The direct address is left
// out when it IS the public one: a second copy would only be tried twice. The
// rest of the machine's addresses reach a device after pairing, in the
// greeting (§3).
//
// Pairing through the onion address works - the first device included
// (FR-008): the connection from tor arrives on the same port as any other and
// proves itself the same way.
func buildLink(serverKey ed25519.PublicKey, token, direct string, conf configuredAddresses) (string, linkCarries, error) {
	addrs := make([]string, 0, 2)
	if conf.Public != "" {
		addrs = append(addrs, conf.Public)
	}
	if direct != "" && direct != conf.Public {
		addrs = append(addrs, direct)
	}
	link, err := BuildPairingLink(serverKey, token, addrs, conf.OnionKey)
	if err != nil {
		return "", linkCarries{}, err
	}
	return link, linkCarries{Public: conf.Public != "", Onion: conf.OnionKey != nil}, nil
}

// pairingLink is buildLink over the addresses stored right now - read per
// link rather than from the address snapshot, so an address set on the service
// page is in the very next code drawn (SC-003) even before the watcher has
// taken its next look.
func (s *Server) pairingLink(ctx context.Context, id store.ServerIdentity, direct, token string) (string, linkCarries, error) {
	conf, err := s.configuredAddresses(ctx)
	if err != nil {
		return "", linkCarries{}, fmt.Errorf("read addresses: %w", err)
	}
	return buildLink(id.PublicKey, token, direct, conf)
}

// listenAddress turns a bind address into one a device can actually reach.
//
// A wildcard bind has no single right answer, so it falls back to loopback:
// right for a machine link with no dialable address, which is handed out on the
// machine itself and pasted into the app running there. An INVITE link is a
// different case and must not use this - see inviteAddress.
func listenAddress(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	// JoinHostPort brackets an IPv6 literal itself. Doing it here as well
	// produced "[[::1]]:8080", which this file's own parser then rejects - so
	// a server bound to an IPv6 address printed no link at all.
	return net.JoinHostPort(host, port)
}

// inviteAddress is the address to put in a link that will be carried to ANOTHER
// device.
//
// listenAddress is wrong here whenever the server is bound to a wildcard: the
// loopback it falls back to is reachable from the machine and from nowhere
// else, so every invite issued by a server bound to 0.0.0.0 - the ordinary way
// to run one for a household - produced a link no phone could dial. Nothing in
// the config says which address is the reachable one, but the device asking for
// the invite is connected over one that demonstrably is, and the Host header is
// exactly that address.
//
// Trust: the header is written by the requesting device, which is already
// paired and is asking for a link to show to itself. It cannot point anyone at
// another server, because the link also carries THIS server's public key and a
// token only this server will accept - a wrong host just yields a link that
// does not connect.
func inviteAddress(cfgAddr, requestHost string) string {
	host, port, err := net.SplitHostPort(cfgAddr)
	if err != nil {
		return listenAddress(cfgAddr)
	}
	if host != "" && host != "0.0.0.0" && host != "::" {
		// An explicitly configured address is a decision; keep it.
		return listenAddress(cfgAddr)
	}
	if requestHost == "" {
		return listenAddress(cfgAddr)
	}
	reachedHost, reachedPort, err := net.SplitHostPort(requestHost)
	if err != nil {
		// No port in the header: the whole value is the host, and the port is
		// the one this server is actually listening on.
		reachedHost, reachedPort = requestHost, port
	}
	if reachedHost == "" || reachedPort == "" {
		return listenAddress(cfgAddr)
	}
	return net.JoinHostPort(reachedHost, reachedPort)
}
