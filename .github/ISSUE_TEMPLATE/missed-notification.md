---
name: "Missed notification"
about: "githud hid something I needed to act on"
title: "Missed: "
labels: ["trust-log", "miss"]
assignees: []
---

<!--
This is a trust log, not a bug report. githud's entire premise is that it
never silently hides something that needed you. A miss is the one failure
that matters most — thank you for reporting it. Keep it short; a few facts
are more useful than a long writeup.
-->

**What happened?**
<!-- The thread/PR/issue that needed you, and what you had to do about it. -->

**What did githud show (or hide)?**
<!-- Did it not appear at all? Appear but ranked low? Show up in the
     suppressed set (`githud probe --show-suppressed`)? -->

**Notification reason (if known)**
<!-- e.g. review_requested, mention, author, assign, comment, team_mention —
     from the GitHub API `reason` field, or "unknown" if you didn't check. -->

**When did this happen?**
<!-- Timestamp or rough time — helps line it up with a specific poll. -->

**Anything else?**
<!-- Repo visibility (public/private), bot vs human actor, or anything that
     might explain why the classifier called it wrong. Optional. -->
