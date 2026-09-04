package server

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
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
// A server bound to every interface prints a loopback link rather than
// "0.0.0.0:8080", which no device can dial.
func listenAddress(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	return net.JoinHostPort(host, port)
}
