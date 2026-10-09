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
// connection to the service at all. One per device (devices.access_key),
// switched off by the write that already ends the device: deleting its row.
//
// The one-time keys onion invites used to carry are gone (feature 044): the
// version-3 link has no field for one, and pairing through the onion service
// waits for 045, which retires access keys altogether.

// ErrAccessKeyTaken is returned for an access key that another device already
// holds. A device makes its own key (contract §8A), and a key two devices share
// would survive the revocation of either.
var ErrAccessKeyTaken = errors.New("access key already in use")

// accessKeyTaken reports whether accessKey belongs to any device but deviceKey.
func accessKeyTaken(ctx context.Context, tx *sql.Tx, deviceKey, accessKey string) (bool, error) {
	var n int
	if err := tx.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM devices WHERE access_key = ? AND device_key <> ?",
		accessKey, deviceKey).Scan(&n); err != nil {
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

// ActiveAccessKeys returns every access key that should open the onion
// service - the devices' own - sorted and without repeats.
//
// DISTINCT because two rows holding one key would be one client to tor, and
// how tor takes the same ClientAuthV3 twice is not something to find out in
// production. The unique index makes a repeat impossible today; the query does
// not lean on it.
func (s *Store) ActiveAccessKeys(ctx context.Context) ([]string, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT DISTINCT access_key FROM devices WHERE access_key IS NOT NULL ORDER BY 1")
	if err != nil {
		return nil, fmt.Errorf("read access keys: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var keys []string
	for rows.Next() {
		var k string
		if err := rows.Scan(&k); err != nil {
			return nil, fmt.Errorf("scan access key: %w", err)
		}
		keys = append(keys, k)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate access keys: %w", err)
	}
	return keys, nil
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
