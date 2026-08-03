// screen-locked.swift — exit 0 if the login-session screen is LOCKED, else 1
// (exit 2 if unknown). A locked screen makes `screencapture` grab the lock screen
// instead of app windows — a FALSE "pixel_live" green. visual-proof.sh checks this
// before it claims a capture.
import CoreGraphics
import Foundation

guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { exit(2) }
exit(((dict["CGSSessionScreenIsLocked"] as? Int) ?? 0) == 1 ? 0 : 1)
