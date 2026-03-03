import { html, nothing } from "lit";
import type { AppViewState } from "../app-view-state.ts";

/** Renders API key warning modal on Agents tab when agentsModelKeyModalError is set (Scenario 1: tab open). */
export function renderApiKeyModal(state: AppViewState) {
  if (state.tab !== "agents" || !state.agentsModelKeyModalError) {
    return nothing;
  }
  const m = state.agentsModelKeyModalError;
  const provider = m.match(/"([^"]+)"/)?.[1] ?? "unknown";
  return html`
    <div class="api-key-modal-overlay" role="dialog" aria-modal="true" aria-labelledby="api-key-modal-title" aria-live="polite">
      <div class="api-key-modal-card">
        <div class="api-key-modal-header">
          <span class="api-key-modal-title" id="api-key-modal-title">⚠️ API Key Invalid</span>
          <button
            class="api-key-modal-close"
            aria-label="Dismiss"
            @click=${() => (state.agentsModelKeyModalError = null)}
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
          <button class="btn primary" @click=${() => (state.agentsModelKeyModalError = null)}>
            Dismiss
          </button>
        </div>
      </div>
    </div>
  `;
}
