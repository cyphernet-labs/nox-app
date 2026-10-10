package main

import (
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/backup"
	"nox.app/client-backend/internal/store"
)

// A restore lets in every device the backup does, one revoked since among
// them, so the person who restored is shown the list - with the backup's
// moment and what to do about such a device - and never a device's key.
func TestARestoreNamesTheDevicesItLetsIn(t *testing.T) {
	made := time.Date(2026, 10, 8, 14, 3, 0, 0, time.UTC)
	out := restoredDevices(backup.Restored{MadeAt: made, Devices: []store.Device{
		{DeviceKey: "a2V5LW9mLXRoZS1waG9uZQ", Platform: "android",
			CreatedAt: time.Date(2026, 9, 1, 10, 12, 0, 0, time.UTC).Unix(), LastSeenAt: made.Add(-time.Hour).Unix()},
		{DeviceKey: "a2V5LW9mLXRoZS1sYXB0b3A", Platform: "macos",
			CreatedAt: time.Date(2026, 9, 15, 18, 40, 0, 0, time.UTC).Unix(), LastSeenAt: made.Unix()},
	}}, time.UTC)
	for _, want := range []string{
		"The backup was made 2026-10-08 14:03 UTC.",
		"android  paired 2026-09-01 10:12 UTC, last seen 2026-10-08 13:03 UTC",
		"macos    paired 2026-09-15 18:40 UTC, last seen 2026-10-08 14:03 UTC",
		"revoked after the backup was made is on this list and can connect again",
		"Settings > Devices",
		"A device paired after the backup is not on it, and has to pair again.",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("the report lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "a2V5") {
		t.Fatalf("the report carries a device key:\n%s", out)
	}

	none := restoredDevices(backup.Restored{MadeAt: made}, time.UTC)
	if !strings.Contains(none, "No device was paired then") || strings.Contains(none, "revoked") {
		t.Fatalf("the report for a backup with no device:\n%s", none)
	}
}
