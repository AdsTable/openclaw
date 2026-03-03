#!/bin/sh
# Post-merge hook: warns if upstream merge may have overwritten customizations.

CUSTOM_FILES="
src/gateway/server-methods-list.ts
src/gateway/server-methods/agents.ts
ui/src/ui/app-render.ts
ui/src/ui/app-settings.ts
ui/src/ui/app-view-state.ts
ui/src/ui/app.ts
ui/src/ui/views/agents-utils.ts
ui/src/ui/views/agents.ts
ui/src/ui/components/modal.ts
ui/src/ui/markdown.ts
ui/src/ui/views/sessions.ts
ui/src/styles/components.css
src/gateway/control-ui.ts
"

echo ""
echo "========================================"
echo "  POST-MERGE: Checking customizations"
echo "========================================"

MISSING=0
for f in $CUSTOM_FILES; do
  case "$f" in
    *agents-utils.ts)
      grep -q "current" "$f" 2>/dev/null || { echo "WARNING: $f lost ← current label"; MISSING=1; }
      grep -q "invalidProviders" "$f" 2>/dev/null || { echo "WARNING: $f lost invalidProviders param"; MISSING=1; }
      ;;
    *server-methods-list.ts)
      grep -q "agents.auth.check" "$f" 2>/dev/null || { echo "WARNING: $f lost agents.auth.check"; MISSING=1; }
      ;;
    *server-methods/agents.ts)
      grep -q "agents.auth.check" "$f" 2>/dev/null || { echo "WARNING: $f lost auth check handler"; MISSING=1; }
      ;;
    *app-settings.ts)
      grep -q "agentsModelKeyModalError" "$f" 2>/dev/null || { echo "WARNING: $f lost Scenario 1 modal check"; MISSING=1; }
      ;;
    *app-render.ts)
      grep -q "agentsModelKeyError" "$f" 2>/dev/null || { echo "WARNING: $f lost model key error handling"; MISSING=1; }
      ;;
    *app-view-state.ts)
      grep -q "agentsModelKeyModalError" "$f" 2>/dev/null || { echo "WARNING: $f lost agentsModelKeyModalError type"; MISSING=1; }
      ;;
    *app.ts)
      grep -q "agentsModelKeyModalError" "$f" 2>/dev/null || { echo "WARNING: $f lost @state agentsModelKeyModalError"; MISSING=1; }
      ;;
    *views/agents.ts)
      grep -q "modelKeyError" "$f" 2>/dev/null || { echo "WARNING: $f lost modelKeyError prop"; MISSING=1; }
      ;;
    *components/modal.ts)
      grep -q "agentsModelKeyModalError" "$f" 2>/dev/null || { echo "WARNING: $f lost modal implementation"; MISSING=1; }
      ;;
    *components.css)
      grep -q "api-key-modal" "$f" 2>/dev/null || { echo "WARNING: $f lost api-key-modal CSS"; MISSING=1; }
      ;;
    *markdown.ts)
      grep -q "isLikelyPathologicalMarkdown" "$f" 2>/dev/null || { echo "WARNING: $f lost pathological markdown guard"; MISSING=1; }
      ;;
  esac
done

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "CRITICAL: Customizations lost! Re-apply from latest patch:"
  echo "  git apply docs/patches/\$(ls -t docs/patches/ | head -1)"
  echo "  OR review CUSTOMIZATIONS.md and re-apply manually."
else
  echo "OK: All customization markers present."
fi
echo "========================================"
echo ""
