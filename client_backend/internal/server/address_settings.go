package server

import (
	"context"
	"crypto/ed25519"
	"crypto/sha3"
	"encoding/base32"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"regexp"
	"strconv"
	"strings"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/store"
)

// The two addresses this machine stores (feature 045): a public host:port and
// the onion address of the service a SEPARATE tor publishes for it. The server
// does not run tor and holds none of its keys; the onion address is a string it
// is told, checked here before it is written and handed on to devices.
//
// Both reach the database by two roads - a start parameter, and the Set button
// on the service page - and both roads go through normalizeAddress, so nothing
// is written that a device could not use.

const (
	// onionPort is the virtual port of the onion service: always 443, so the
	// address a device keeps does not change when -addr moves the port tor
	// forwards to (contract §1).
	onionPort = "443"
	// onionNameLen is the 56 base32 characters of a v3 onion address: 35 bytes,
	// exactly, so every such string decodes to one value and no other.
	onionNameLen = 56
	// onionVersion is the version byte that ends a v3 address.
	onionVersion = 0x03
	// maxLabelBytes is DNS's limit on one label of a name.
	maxLabelBytes = 63
)

// onionAlphabet is RFC 4648 base32 in the lower case an onion address is
// written in, without padding.
var onionAlphabet = base32.NewEncoding("abcdefghijklmnopqrstuvwxyz234567").WithPadding(base32.NoPadding)

// onionName is the shape of the name before ".onion". Checked before decoding:
// the base32 decoder skips line breaks, and an address with one inside is not
// the address the owner meant.
var onionName = regexp.MustCompile(`^[a-z2-7]{56}$`)

// The two refusals of an address. They name the rule, never the value: a log
// line or a page built from the error must not carry what was refused, which
// for an onion address is very nearly the address itself.
var (
	errInvalidOnion  = errors.New("not a valid onion address")
	errInvalidPublic = errors.New("not a valid address: use host:port")
)

// parseOnionAddress checks a v3 onion address the way rend-spec-v3 §6 defines
// one - 56 lowercase base32 characters, then ".onion", optionally ":443" - and
// returns it in its stored form, without the port, together with the service's
// public key, which is what a pairing link carries.
//
// The 35 decoded bytes are the key (32), a checksum (2) and the version (1);
// the checksum is the first two bytes of SHA3-256(".onion checksum" ‖ key ‖
// version). A typo in any character fails it with near certainty, which is the
// point: a wrong onion address sends every device away from home to nobody.
func parseOnionAddress(raw string) (string, ed25519.PublicKey, error) {
	host := raw
	if h, port, err := net.SplitHostPort(raw); err == nil {
		// The service's port is fixed. Any other one is a different service,
		// or a mistake - either way not this machine's address.
		if port != onionPort {
			return "", nil, errInvalidOnion
		}
		host = h
	}
	name, ok := strings.CutSuffix(host, ".onion")
	if !ok || !onionName.MatchString(name) {
		return "", nil, errInvalidOnion
	}
	decoded, err := onionAlphabet.DecodeString(name)
	if err != nil || len(decoded) != ed25519.PublicKeySize+3 {
		return "", nil, errInvalidOnion
	}
	key := decoded[:ed25519.PublicKeySize]
	if decoded[ed25519.PublicKeySize+2] != onionVersion {
		return "", nil, errInvalidOnion
	}
	sum := onionChecksum(key)
	if decoded[ed25519.PublicKeySize] != sum[0] || decoded[ed25519.PublicKeySize+1] != sum[1] {
		return "", nil, errInvalidOnion
	}
	return name + ".onion", ed25519.PublicKey(key), nil
}

// onionChecksum is SHA3-256(".onion checksum" ‖ key ‖ version), of which an
// address carries the first two bytes.
func onionChecksum(key []byte) [32]byte {
	input := make([]byte, 0, len(".onion checksum")+len(key)+1)
	input = append(input, ".onion checksum"...)
	input = append(input, key...)
	input = append(input, onionVersion)
	return sha3.Sum256(input)
}

// parsePublicAddress checks a public address - host:port, the host an IP
// literal (IPv6 in brackets) or a DNS name, the port 1-65535 - and returns it
// in one spelling: the IP as Go prints it, the name in lower case without a
// trailing dot, the port without leading zeros.
//
// Everything accepted here goes into pairing links, so it is held to what the
// link builder can encode: a name of at most 253 bytes and no zone on an IPv6
// address. A link that cannot be built would leave the machine with no claim
// link and no invites at all.
func parsePublicAddress(raw string) (string, error) {
	host, portStr, err := net.SplitHostPort(raw)
	if err != nil || host == "" {
		return "", errInvalidPublic
	}
	// Digits only: ParseUint takes no sign, and a service name such as "https"
	// is a port the device would have to look up.
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil || port == 0 {
		return "", errInvalidPublic
	}
	if ip := net.ParseIP(host); ip != nil {
		return net.JoinHostPort(ip.String(), strconv.FormatUint(port, 10)), nil
	}
	name := strings.ToLower(strings.TrimSuffix(host, "."))
	if !validHostName(name) {
		return "", errInvalidPublic
	}
	// An onion name is not a public address: dialled directly it reaches
	// nothing, and it belongs in the field next to this one.
	if strings.HasSuffix(name, ".onion") {
		return "", errInvalidPublic
	}
	return net.JoinHostPort(name, strconv.FormatUint(port, 10)), nil
}

// validHostName is the DNS rule for a name a device can dial: at most 253
// bytes, labels of 1-63 letters, digits and hyphens that neither start nor end
// with a hyphen, and a last label that is not all digits - which is what
// catches "192.168.1.300", a mistyped address that would otherwise pass as a
// name and fail only on the device.
func validHostName(name string) bool {
	if name == "" || len(name) > maxLinkNameBytes {
		return false
	}
	labels := strings.Split(name, ".")
	for _, label := range labels {
		if label == "" || len(label) > maxLabelBytes || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, c := range []byte(label) {
			if (c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '-' {
				return false
			}
		}
	}
	last := labels[len(labels)-1]
	return strings.Trim(last, "0123456789") != ""
}

// normalizeAddress checks a value for one of the two stored addresses and
// returns the form it is stored in. Empty is empty: on the service page it
// deletes the address.
func normalizeAddress(kind store.AddressKind, raw string) (string, error) {
	if raw == "" {
		return "", nil
	}
	switch kind {
	case store.AddressPublic:
		return parsePublicAddress(raw)
	case store.AddressOnion:
		addr, _, err := parseOnionAddress(raw)
		return addr, err
	}
	return "", store.ErrUnknownAddressKind
}

// configuredAddresses is what the stored addresses offer right now, each one
// that reads back as valid: the public host:port, the onion address without
// its port, and the onion service's key for the pairing link.
type configuredAddresses struct {
	Public   string
	Onion    string
	OnionKey ed25519.PublicKey
}

// configured keeps the stored addresses that are valid. Only a hand edit of
// the database can store anything else - both roads in check first - and an
// address no device can use is better left out of links and greetings than
// handed to every device.
func configured(stored store.Addresses) configuredAddresses {
	var out configuredAddresses
	if public, err := parsePublicAddress(stored.Public); err == nil {
		out.Public = public
	}
	if onion, key, err := parseOnionAddress(stored.Onion); err == nil {
		out.Onion, out.OnionKey = onion, key
	}
	return out
}

// configuredAddresses reads the stored addresses and keeps the valid ones.
func (s *Server) configuredAddresses(ctx context.Context) (configuredAddresses, error) {
	stored, err := s.store.Addresses(ctx)
	if err != nil {
		return configuredAddresses{}, err
	}
	return configured(stored), nil
}

// addressWarning is a start parameter that was not applied: the service page
// names it until the next start, and the start after that names it again
// unless it was fixed, because a refused parameter is never remembered as
// applied.
type addressWarning struct {
	Kind store.AddressKind
}

// paramFlag is the start parameter of kind, spelled the way the log, the page
// and the operator's unit file spell it.
func paramFlag(kind store.AddressKind) string {
	if kind == store.AddressOnion {
		return "-onion-addr"
	}
	return "-public-addr"
}

// applyAddressParams writes each start parameter that appeared or changed
// since the last start, before any listener opens (FR-003).
//
// "Changed" is measured against the parameter last APPLIED, not against the
// stored address: an address set on the service page then survives a restart
// with the same parameter still in the unit file, and an install script that
// writes the parameter once does not overwrite the owner's later edits on
// every boot.
//
// A parameter that does not check out is not applied and does not stop the
// start: a machine that rebooted with nobody at it must not stop every
// conversation over a typo. It keeps the address it had, says so in the log
// and on the service page, and is not remembered - so the warning comes back
// on every start until the parameter is fixed. An empty parameter changes
// nothing; only the page deletes an address.
func applyAddressParams(ctx context.Context, st *store.Store, cfg config.Config, logger *slog.Logger) ([]addressWarning, error) {
	stored, err := st.Addresses(ctx)
	if err != nil {
		return nil, fmt.Errorf("read addresses: %w", err)
	}
	var warnings []addressWarning
	for _, p := range []struct {
		kind  store.AddressKind
		param string
	}{
		{store.AddressPublic, cfg.PublicAddr},
		{store.AddressOnion, cfg.OnionAddr},
	} {
		if p.param == "" || p.param == stored.Param(p.kind) {
			continue
		}
		value, err := normalizeAddress(p.kind, p.param)
		if err != nil {
			// The value stays out of the line for an onion address, which a
			// typo leaves one character away from the real one (FR-022). A
			// public address is not a secret - every device is told it - and
			// is named; an onion name pasted into the wrong parameter, which
			// is exactly what this branch catches, is masked by the log's
			// own handler (logscrub.go).
			attrs := []any{"param", paramFlag(p.kind), "reason", err.Error()}
			if p.kind == store.AddressPublic {
				attrs = append(attrs, "value", p.param)
			}
			logger.Error("start parameter not applied, the server keeps the address it has", attrs...)
			warnings = append(warnings, addressWarning{Kind: p.kind})
			continue
		}
		if err := st.ApplyAddressParam(ctx, p.kind, value, p.param); err != nil {
			return nil, fmt.Errorf("apply %s: %w", paramFlag(p.kind), err)
		}
		logger.Info("start parameter applied", "param", paramFlag(p.kind))
	}

	// A stored address that does not check out came from a hand edit. Said
	// once, here, rather than on every look the address watcher takes.
	after, err := st.Addresses(ctx)
	if err != nil {
		return nil, fmt.Errorf("read addresses: %w", err)
	}
	conf := configured(after)
	if after.Public != "" && conf.Public == "" {
		logger.Error("the stored public address is not valid and is left out until it is set again on the service page")
	}
	if after.Onion != "" && conf.Onion == "" {
		logger.Error("the stored onion address is not valid and is left out until it is set again on the service page")
	}
	return warnings, nil
}

// onionHost reports whether a Host header names an onion service. It is the
// only sign left that a request came through tor (045): the connection itself
// arrives on the main port like any other.
func onionHost(hostHeader string) bool {
	host, _, err := net.SplitHostPort(hostHeader)
	if err != nil {
		host = hostHeader
	}
	return strings.HasSuffix(strings.ToLower(strings.TrimSuffix(host, ".")), ".onion")
}
