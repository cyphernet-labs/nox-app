package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

func isNoRows(err error) bool { return errors.Is(err, sql.ErrNoRows) }

// Device is one authorised install of a person, as shown in the device list.
//
// Platform is the OS family and nothing more: enough to recognise one's own
// tablet among three, while the exact hardware model would be a fingerprint the
// server has no business keeping.
type Device struct {
	DeviceKey  string `json:"device_key"`
	Platform   string `json:"platform"`
	CreatedAt  int64  `json:"created_at"`
	LastSeenAt int64  `json:"last_seen_at"`
}

// ListDevices returns every device authorised for a person, oldest first.
func (s *Store) ListDevices(ctx context.Context, userID string) ([]Device, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT device_key, platform, created_at, last_seen_at FROM devices WHERE user_id = ? ORDER BY created_at",
		userID)
	if err != nil {
		return nil, fmt.Errorf("list devices: %w", err)
	}
	defer func() { _ = rows.Close() }()

	devices := make([]Device, 0, 4)
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.DeviceKey, &d.Platform, &d.CreatedAt, &d.LastSeenAt); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate devices: %w", err)
	}
	return devices, nil
}

// RevokeDevice removes a key from the allowed list.
//
// Deletion rather than a revoked_at flag: a third state would have to be
// remembered at every lookup, while deletion buys the property the client needs
// for free - a revoked device becomes indistinguishable from an unknown one,
// which is also what a rebuilt store looks like, and both mean the same thing
// to the device.
//
// Revoking a key that is not there is a SUCCESS: the caller asked for a state,
// and that state already holds. Reporting an error would make a retry after a
// dropped connection look like a failure.
//
// The person's row is deliberately left alone, even when this was their last
// device: an identity has to survive losing every device, or recovery would
// have nothing to reattach to.
func (s *Store) RevokeDevice(ctx context.Context, deviceKey string) error {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin revoke device: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var userID string
	err = tx.QueryRowContext(ctx, "SELECT user_id FROM devices WHERE device_key = ?", deviceKey).Scan(&userID)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		// Already gone. Nothing to revoke and nothing to retire.
		return tx.Commit()
	case err != nil:
		return fmt.Errorf("read device before revoke: %w", err)
	}

	if _, err := tx.ExecContext(ctx, "DELETE FROM devices WHERE device_key = ?", deviceKey); err != nil {
		return fmt.Errorf("revoke device: %w", err)
	}
	// Live invites of this person die with it. A revoked device may well have
	// issued one minutes ago, and leaving it usable would let whoever holds
	// that link walk straight back in - the revocation would have removed the
	// key and left the door it opened.
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ? WHERE user_id = ? AND used_at IS NULL",
		time.Now().Unix(), userID); err != nil {
		return fmt.Errorf("retire invites: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit revoke device: %w", err)
	}
	return nil
}

// DeviceOwner reports which person a key belongs to, so a caller can refuse to
// revoke somebody else's device.
func (s *Store) DeviceOwner(ctx context.Context, deviceKey string) (string, bool, error) {
	var userID string
	err := s.read.QueryRowContext(ctx,
		"SELECT user_id FROM devices WHERE device_key = ?", deviceKey).Scan(&userID)
	if err != nil {
		if isNoRows(err) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("read device owner: %w", err)
	}
	return userID, true, nil
}

// SetLabel renames a person. Contract §8A: names are not unique and the server
// neither enforces nor reports uniqueness, so there is nothing here to refuse.
func (s *Store) SetLabel(ctx context.Context, userID, label string) error {
	if _, err := s.write.ExecContext(ctx,
		"UPDATE users SET label = ? WHERE user_id = ?", label, userID); err != nil {
		return fmt.Errorf("set label: %w", err)
	}
	return nil
}

// CountDevices reports how many keys can still reach this server at all.
//
// Zero means nobody can: the claim is spent, every device is revoked, and
// without this the machine would be locked forever - the identity survives,
// which is the point, but nothing could ever attach to it again.
func (s *Store) CountDevices(ctx context.Context) (int, error) {
	var n int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM devices").Scan(&n); err != nil {
		return 0, fmt.Errorf("count devices: %w", err)
	}
	return n, nil
}

// CountUsers reports how many people the server knows. Test-support.
func (s *Store) CountUsers(ctx context.Context) (int, error) {
	var n int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&n); err != nil {
		return 0, fmt.Errorf("count users: %w", err)
	}
	return n, nil
}

// AnyUser returns some person's id. Test-support for a server that holds
// exactly one until invite-user arrives (Q15).
func (s *Store) AnyUser(ctx context.Context) (string, error) {
	var id string
	if err := s.read.QueryRowContext(ctx, "SELECT user_id FROM users LIMIT 1").Scan(&id); err != nil {
		return "", fmt.Errorf("read any user: %w", err)
	}
	return id, nil
}
