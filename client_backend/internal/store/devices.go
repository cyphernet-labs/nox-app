package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

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

// Revocation is what revoking a device set in motion besides the row itself.
type Revocation struct {
	// Closed are the requests the revoked device took part in, now closed -
	// denied, or expired when their time had already run out - so the devices
	// on the other side of each can be told.
	Closed []PairRequest
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
// device: the person and every conversation outlive their devices, and the
// machine link joins the next device to them (FR-015).
func (s *Store) RevokeDevice(ctx context.Context, deviceKey string, now int64) (Revocation, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return Revocation{}, fmt.Errorf("begin revoke device: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var userID string
	err = tx.QueryRowContext(ctx, "SELECT user_id FROM devices WHERE device_key = ?", deviceKey).Scan(&userID)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		// Already gone. Nothing to revoke and nothing to retire: everything
		// below happened when it went.
		return Revocation{}, tx.Commit()
	case err != nil:
		return Revocation{}, fmt.Errorf("read device before revoke: %w", err)
	}

	if _, err := tx.ExecContext(ctx, "DELETE FROM devices WHERE device_key = ?", deviceKey); err != nil {
		return Revocation{}, fmt.Errorf("revoke device: %w", err)
	}
	// The requests it takes part in close as denied: nobody is left to press
	// Allow on the ones it was asked to answer, and the person who revoked it
	// is not to be asked to let it back in on one it opened.
	closed, err := closeRequestsOf(ctx, tx, deviceKey, now)
	if err != nil {
		return Revocation{}, err
	}
	// The invites it issued that nobody has presented die with it. Leaving one
	// usable would let whoever holds that link ask the person's OTHER devices to
	// let them in on the authority of a device that was just told to leave. The
	// invites of the person's other devices are theirs and stay.
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ? WHERE issuer_key = ? AND used_at IS NULL", now, deviceKey); err != nil {
		return Revocation{}, fmt.Errorf("void the device's invites: %w", err)
	}
	// The last device going away puts the machine back to "no devices", where
	// the service page shows a machine link at once (FR-015). A machine link that
	// already ran out unused would stand in the way - the page shows an unspent
	// link as "Link expired" rather than minting over it - so it is voided here.
	// A live one stays: it is the link somebody may be scanning right now.
	devices, err := countDevices(ctx, tx)
	if err != nil {
		return Revocation{}, err
	}
	if devices == 0 {
		if _, err := tx.ExecContext(ctx,
			"UPDATE pair_tokens SET used_at = ? WHERE kind = ? AND used_at IS NULL AND expires_at <= ?",
			now, TokenMachine, now); err != nil {
			return Revocation{}, fmt.Errorf("void a machine link that ran out: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return Revocation{}, fmt.Errorf("commit revoke device: %w", err)
	}
	return Revocation{Closed: closed}, nil
}

// DeviceOwner reports which person a key belongs to, so a caller can refuse to
// revoke somebody else's device.
func (s *Store) DeviceOwner(ctx context.Context, deviceKey string) (string, bool, error) {
	owner, err := deviceOwnerOf(ctx, s.read, deviceKey)
	if err != nil {
		return "", false, err
	}
	return owner, owner != "", nil
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
