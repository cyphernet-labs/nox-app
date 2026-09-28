package server

import (
	"crypto/ed25519"
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
	// pairingLinkVersionOnion is the onion invite (039): version 1's fields,
	// then the onion service's public key, its port, and the one-time access
	// key's PRIVATE half. Only device.invite with onion: true produces it; a
	// claim never does.
	pairingLinkVersionOnion = 2
	pairingLinkPrefix       = "https://nox.app/p/#"

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
func BuildPairingLink(addr, serverFingerprint, token string) (string, error) {
	payload, err := linkPayload(pairingLinkVersion, addr, serverFingerprint, token)
	if err != nil {
		return "", err
	}
	return pairingLinkPrefix + base64.RawURLEncoding.EncodeToString(payload), nil
}

// BuildPairingLinkV2 renders an onion invite (039): everything version 1
// carries, then onion_pub (32), onion_port (2, big-endian) and one_time_priv
// (32) - contract §8A.
//
// The field names say which half each key is, because the two kinds would
// otherwise read alike: onion_pub is PUBLIC, one_time_priv is the PRIVATE
// half of a one-time key whose public half is all the server keeps.
func BuildPairingLinkV2(addr, serverFingerprint, token string, onionPub ed25519.PublicKey, onionPort int, oneTimePriv []byte) (string, error) {
	if len(onionPub) != ed25519.PublicKeySize {
		return "", errors.New("onion public key is not 32 bytes")
	}
	if onionPort <= 0 || onionPort > 0xffff {
		return "", errors.New("onion port out of range")
	}
	if len(oneTimePriv) != 32 {
		return "", errors.New("one-time access key is not 32 bytes")
	}
	payload, err := linkPayload(pairingLinkVersionOnion, addr, serverFingerprint, token)
	if err != nil {
		return "", err
	}
	payload = append(payload, onionPub...)
	payload = binary.BigEndian.AppendUint16(payload, uint16(onionPort))
	payload = append(payload, oneTimePriv...)
	return pairingLinkPrefix + base64.RawURLEncoding.EncodeToString(payload), nil
}

// linkPayload is the part both versions share: version, host, port,
// fingerprint, token.
func linkPayload(version byte, addr, serverFingerprint, token string) ([]byte, error) {
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, fmt.Errorf("split pairing address: %w", err)
	}
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		return nil, fmt.Errorf("parse pairing port: %w", err)
	}

	fingerprint, err := base64.StdEncoding.DecodeString(serverFingerprint)
	if err != nil || len(fingerprint) != 32 {
		return nil, errors.New("server fingerprint is not 32 bytes")
	}
	tok, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(tok) != 16 {
		return nil, errors.New("token is not 16 bytes")
	}

	payload := []byte{version}
	switch ip := net.ParseIP(host); {
	case ip == nil:
		if len(host) == 0 || len(host) > 255 {
			return nil, errors.New("host name does not fit the link")
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
	payload = append(payload, fingerprint...)
	payload = append(payload, tok...)
	return payload, nil
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
