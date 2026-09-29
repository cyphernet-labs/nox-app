package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// Onion access keys (feature 039).
//
// An access key is an x25519 PUBLIC key that tor puts in the onion service's
// list of authorised clients: without one in the list, tor will not build a
// connection to the service at all. Two kinds live in the store - one per
// device (devices.access_key) and one per onion invite (pair_tokens.access_key,
// the public half of a one-time key whose private half only the link carries).
// Both are switched off by the same writes that already end what they belong
// to: deleting the device row, or spending, expiring or burning the token.

// ErrAccessKeyTaken is returned for an access key that is already somebody
// else's: another device holds it, or an onion invite was issued with it. A
// device makes its own key (contract §8A), and the two cases are the two ways a
// key outlives what is meant to end it. A key two devices share survives the
// revocation of either; a one-time key's private half travels in a link - a QR,
// perhaps a screenshot - and must never become anybody's permanent key.
var ErrAccessKeyTaken = errors.New("access key already in use")

// accessKeyTaken reports whether accessKey belongs to anything but the device
// deviceKey. Every onion invite counts - live, spent or expired - because the
// link holding a one-time key's private half outlives the token, and token rows
// are never deleted.
func accessKeyTaken(ctx context.Context, tx *sql.Tx, deviceKey, accessKey string) (bool, error) {
	var n int
	if err := tx.QueryRowContext(ctx, `
		SELECT (SELECT COUNT(1) FROM devices WHERE access_key = ? AND device_key <> ?)
		     + (SELECT COUNT(1) FROM pair_tokens WHERE access_key = ?)`,
		accessKey, deviceKey, accessKey).Scan(&n); err != nil {
		return false, fmt.Errorf("check access key: %w", err)
	}
	return n > 0, nil
}

// SetAccessKey registers a device's access key, replacing any it had: one per
// device. changed is false when the device already had exactly this key, so the
// caller can skip a republish that would cut every onion connection for
// nothing.
//
// A device that is no longer there gets ErrDeviceUnknown - revoked in the
// middle of its session - which the wire answers exactly as it answers that
// device's next greeting. A key that is somebody else's gets
// ErrAccessKeyTaken.
func (s *Store) SetAccessKey(ctx context.Context, deviceKey, accessKey string) (changed bool, err error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("begin set access key: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var current sql.NullString
	err = tx.QueryRowContext(ctx, "SELECT access_key FROM devices WHERE device_key = ?", deviceKey).Scan(&current)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrDeviceUnknown
	}
	if err != nil {
		return false, fmt.Errorf("read access key: %w", err)
	}
	if current.Valid && current.String == accessKey {
		return false, tx.Commit()
	}
	taken, err := accessKeyTaken(ctx, tx, deviceKey, accessKey)
	if err != nil {
		return false, err
	}
	if taken {
		return false, ErrAccessKeyTaken
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE devices SET access_key = ? WHERE device_key = ?", accessKey, deviceKey); err != nil {
		return false, fmt.Errorf("set access key: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return false, fmt.Errorf("commit set access key: %w", err)
	}
	return true, nil
}

// ActiveAccessKeys returns every access key that should open the onion service
// at now - devices' keys and the one-time keys of live onion invites - sorted
// and without repeats, together with the moment the earliest one-time key
// stops working (0 when there is none), so the supervisor can republish
// exactly then.
//
// One read transaction for both answers: two separate reads could straddle a
// pairing that spends a one-time key and adds a device key, and describe a list
// that never existed.
func (s *Store) ActiveAccessKeys(ctx context.Context, now int64) (keys []string, nextExpiry int64, err error) {
	tx, err := s.read.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return nil, 0, fmt.Errorf("begin access keys read: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// UNION, not UNION ALL: two rows holding one key are one client to tor,
	// and how tor takes the same ClientAuthV3 twice is not something to find
	// out in production.
	rows, err := tx.QueryContext(ctx, `
		SELECT access_key FROM devices WHERE access_key IS NOT NULL
		UNION
		SELECT access_key FROM pair_tokens
		 WHERE kind = ? AND access_key IS NOT NULL AND used_at IS NULL AND expires_at > ?
		ORDER BY 1`, TokenInviteDevice, now)
	if err != nil {
		return nil, 0, fmt.Errorf("read access keys: %w", err)
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var k string
		if err := rows.Scan(&k); err != nil {
			return nil, 0, fmt.Errorf("scan access key: %w", err)
		}
		keys = append(keys, k)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate access keys: %w", err)
	}

	var next sql.NullInt64
	if err := tx.QueryRowContext(ctx, `
		SELECT MIN(expires_at) FROM pair_tokens
		 WHERE kind = ? AND access_key IS NOT NULL AND used_at IS NULL AND expires_at > ?`,
		TokenInviteDevice, now).Scan(&next); err != nil {
		return nil, 0, fmt.Errorf("read next access key expiry: %w", err)
	}
	return keys, next.Int64, nil
}

// CountDevicesWithAccess answers "how many of my devices can reach this
// machine from anywhere" for the status page. A count, never the keys: public
// keys of devices are not shown even there.
func (s *Store) CountDevicesWithAccess(ctx context.Context) (int, error) {
	var n int
	if err := s.read.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM devices WHERE access_key IS NOT NULL").Scan(&n); err != nil {
		return 0, fmt.Errorf("count devices with access: %w", err)
	}
	return n, nil
}
