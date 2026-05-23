import { env } from "../config/env.js";

/**
 * Subscription tier definitions and resolution logic.
 *
 * Canonical name: lib/subscription-tiers.js
 * (lib/tiers.js is a backward-compat re-export)
 *
 * @typedef {'free' | 'standard' | 'premium'} SubscriptionTier
 */

const TIERS = /** @type {const} */ (["free", "standard", "premium"]);

/** @param {unknown} value @returns {value is SubscriptionTier} */
export function isSubscriptionTier(value) {
  return typeof value === "string" && TIERS.includes(/** @type {SubscriptionTier} */ (value));
}

/** @param {SubscriptionTier} tier @returns {number} */
export function maxPagesForTier(tier) {
  return env.tierMaxPages[tier];
}

/**
 * Resolves the effective subscription from trusted server-side claims or
 * (in dev only) from client-supplied headers.
 *
 * @param {{
 *   trustedTier?: SubscriptionTier | null;
 *   trustedActive?: boolean | null;
 *   headerTier?: string | undefined;
 *   headerActive?: string | undefined;
 * }} input
 * @returns {{ tier: SubscriptionTier; active: boolean }}
 */
export function resolveSubscription(input) {
  if (input.trustedTier && isSubscriptionTier(input.trustedTier)) {
    return { tier: input.trustedTier, active: input.trustedActive !== false };
  }

  if (env.trustClientTierHeaders) {
    let tier = /** @type {SubscriptionTier} */ ("free");
    const h = input.headerTier?.toLowerCase();
    if (h && isSubscriptionTier(h)) tier = h;
    const a = input.headerActive?.toLowerCase();
    const active = a !== "false" && a !== "0";
    return { tier, active };
  }

  return { tier: "free", active: true };
}
