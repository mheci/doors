# Brave Origin / Fedora 44 signed repository transaction test
Test date (UTC): 2026-09-20T04:36:33Z
- Used Fedora 44 container, downloaded Brave official repo file and signing key over HTTPS, imported the key, and installed with DNF5 without gpgcheck bypasses.
- Candidate resolved: brave-origin 1.95.104-1 from brave-browser.
- rpm -V returned clean; brave-origin --version returned Brave Origin 153.1.95.104 with exit 0.
- --help emitted a Chromium fatal execlp error inside a minimal headless container even though the shell wrapper returned 0. This is not a GNOME/Wayland validation and cannot confirm or disprove the publicly reported Fedora 44 desktop crash.
- No --nogpgcheck, --nodeps, or unsigned package workaround was used.
- Full reproducible log: /home/user/doors/audit/raw/brave-origin-fedora44-test.log
