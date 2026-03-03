import { html, nothing } from "lit";
import type { AppViewState } from "../app-view-state.ts";

/** Renders API key warning modal on Agents tab when agentsModelKeyError is set. */
export function renderApiKeyModal(state: AppViewState) {
  if (state.tab !== "agents" || !state.agentsModelKeyError) {
    return nothing;
  }
  const m = state.agentsModelKeyError;
  const provider = m.match(/"([^"]+)"/)?.[1] ?? "unknown";
  return html`
    <div class="api-key-modal-overlay" role="dialog" aria-modal="true">
      <div class="api-key-modal-card">
        <div class="api-key-modal-header">
          <span class="api-key-modal-title">⚠️ API Key Invalid</span>
          <button
            class="api-key-modal-close"
            aria-label="Dismiss"
            @click=${() => (state.agentsModelKeyError = null)}
          >✕</button>
        </div>
        <div class="api-key-modal-body">
          <p>${m}</p>
          <p class="api-key-modal-hint">
            Fix: update <strong>${provider}</strong> key in
            <code>auth-profiles.json</code> → <code>${provider}:default</code>
          </p>
        </div>
        <div class="api-key-modal-actions">
          <button class="btn primary" @click=${() => (state.agentsModelKeyError = null)}>
            Dismiss
          </button>
        </div>
      </div>
    </div>
  `;
}
