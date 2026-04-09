#!/usr/bin/env bash
# Remediation script for GitHub secret scanning alert #2
# Removes hardcoded Google OAuth client secret from git history
#
# The secret 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 was present in
# extensions/google-antigravity-auth/index.ts (deleted in upstream commit
# 382fe8009a). Although the file no longer exists in the working tree,
# the secret remains in historical commits and triggers GitHub secret scanning.
#
# USAGE (run from repo root, as repository owner):
#   bash dev.docs/scripts/remediate-secret-alert-2.sh
#
# After running, force-push ALL branches:
#   git push origin --force --all
#   git push origin --force --tags
#
# Then in GitHub:
#   Settings → Security → Secret scanning → Alert #2 → Mark as resolved (revoked)

set -euo pipefail

if ! command -v git-filter-repo &>/dev/null; then
  echo "Installing git-filter-repo..."
  pip install git-filter-repo
fi

echo "Creating replacements file..."
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'REPLACEMENTS'
R09DU1BYLUs1OEZXUjQ4NkxkTEoxbUxCOHNYQzR6NnFEQWY===>REDACTED_GOOGLE_OAUTH_CLIENT_SECRET_BASE64
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==>REDACTED_GOOGLE_OAUTH_CLIENT_SECRET
REPLACEMENTS

echo "Running git-filter-repo to redact secret from all commits..."
git-filter-repo --replace-text "$TMPFILE" --force
rm -f "$TMPFILE"

echo ""
echo "Done. History rewritten locally."
echo ""
echo "IMPORTANT: Now force-push all branches to GitHub:"
echo "  git remote add origin https://github.com/AdsTable/openclaw"
echo "  git push origin --force --all"
echo "  git push origin --force --tags"
echo ""
echo "Then dismiss alert #2 at:"
echo "  https://github.com/AdsTable/openclaw/security/secret-scanning/2"
