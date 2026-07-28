# Suggestion: harden flat YAML reader for inline comments

`Read-FlatYaml` in `run-on-docker-server.ps1` / `run-on-docker-local.ps1` treats the rest of the line as the value. A line like `build_image_on: "local"  # comment` fails validation.

**Why it matters:** Easy misconfig; already tripped once during t3 deploy.

**Effort:** Low — strip ` #...` outside quotes after the value match, or document “comments on their own lines only” (current workaround).
