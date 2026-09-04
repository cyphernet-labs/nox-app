package server

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strconv"
)

// Pairing link format, contract §8A. One shape for every case, so there is one
// parser, one scanner and one set of tests.
const (
	pairingLinkVersion = 1
	pairingLinkPrefix  = "https://nox.app/p/#"

	hostTypeIPv4 = 1
	hostTypeIPv6 = 2
	hostTypeDNS  = 3
)

// BuildPairingLink renders the link a person presents to an app.
//
// The host type is written EXPLICITLY rather than inferred while parsing:
// "1.2.3.4" reads as both an IPv4 address and a host name, and one byte
// settles that forever instead of leaving two implementations to disagree.
//
// The payload lives in the fragment because a browser never sends a fragment
// to a server - a link opened in a browser by mistake leaks the token nowhere.
func BuildPairingLink(addr, serverKey, token string) (string, error) {
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return "", fmt.Errorf("split pairing address: %w", err)
	}
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		return "", fmt.Errorf("parse pairing port: %w", err)
	}

	key, err := base64.StdEncoding.DecodeString(serverKey)
	if err != nil || len(key) != 32 {
		return "", errors.New("server key is not 32 bytes")
	}
	tok, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(tok) != 16 {
		return "", errors.New("token is not 16 bytes")
	}

	payload := []byte{pairingLinkVersion}
	switch ip := net.ParseIP(host); {
	case ip == nil:
		if len(host) == 0 || len(host) > 255 {
			return "", errors.New("host name does not fit the link")
		}
		payload = append(payload, hostTypeDNS, byte(len(host)))
		payload = append(payload, host...)
	case ip.To4() != nil:
		payload = append(payload, hostTypeIPv4)
		payload = append(payload, ip.To4()...)
	default:
		payload = append(payload, hostTypeIPv6)
		payload = append(payload, ip.To16()...)
	}

	payload = binary.BigEndian.AppendUint16(payload, uint16(port))
	payload = append(payload, key...)
	payload = append(payload, tok...)

	return pairingLinkPrefix + base64.RawURLEncoding.EncodeToString(payload), nil
}

// listenAddress turns a bind address into one a device can actually reach.
//
// A wildcard bind has no single right answer, so it falls back to loopback:
// right for the claim link, which is printed on the machine itself and dialled
// from it or read by whoever is sitting there. An INVITE link is a different
// case and must not use this - see inviteAddress.
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
