#!/bin/sh
# Pre-push hook: TypeScript check + customization markers verification before push.

echo ""
echo "========================================"
echo "  PRE-PUSH: Verifying before push"
echo "========================================"

# TypeScript check (skip e2e tests)
echo "Running TypeScript check..."
TS_ERRORS=$(npx tsc --noEmit 2>&1 | grep "error TS" | grep -v "e2e.test")
if [ -n "$TS_ERRORS" ]; then
  echo "BLOCKED: TypeScript errors found:"
  echo "$TS_ERRORS"
  echo "Fix errors before pushing."
  exit 1
fi
echo "TypeScript OK."

# Verify customization markers
MISSING=0
grep -q "agents.auth.check" src/gateway/server-methods-list.ts 2>/dev/null || { echo "WARNING: agents.auth.check missing from server-methods-list.ts"; MISSING=1; }
grep -q "agents.auth.check" src/gateway/server-methods/agents.ts 2>/dev/null || { echo "WARNING: agents.auth.check handler missing"; MISSING=1; }
grep -q "agentsModelKeyError" ui/src/ui/app-render.ts 2>/dev/null || { echo "WARNING: agentsModelKeyError missing from app-render.ts"; MISSING=1; }
grep -q "invalidProviders" ui/src/ui/views/agents-utils.ts 2>/dev/null || { echo "WARNING: invalidProviders missing from agents-utils.ts"; MISSING=1; }

if [ "$MISSING" -eq 1 ]; then
  echo "WARNING: Some customizations may be missing. Review CUSTOMIZATIONS.md."
fi

echo "========================================"
echo ""
exit 0
