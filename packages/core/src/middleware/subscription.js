import { env } from "../config/env.js";
import { resolveSubscription } from "../lib/subscription-tiers.js";

/**
 * Attaches `req.subscription` from trusted claims (when you add auth) or client headers in dev.
 * Production: set `req.trustedSubscription` in an upstream auth middleware after verifying JWT/webhook.
 *
 * @typedef {import('../lib/tiers.js').SubscriptionTier} SubscriptionTier
 */

/**
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
export function subscriptionContext(req, res, next) {
  const headerTier = req.get("x-subscription-tier") || req.get("X-Subscription-Tier") || undefined;
  const headerActive = req.get("x-subscription-active") || req.get("X-Subscription-Active") || undefined;

  /** @type {{ trustedTier?: SubscriptionTier | null; trustedActive?: boolean | null }} */
  const trusted = {};
  if (req.trustedSubscription && typeof req.trustedSubscription === "object") {
    const ts = req.trustedSubscription;
    if ("tier" in ts) trusted.trustedTier = /** @type {SubscriptionTier} */ (ts.tier);
    if ("active" in ts) trusted.trustedActive = Boolean(ts.active);
  }

  req.subscription = resolveSubscription({
    ...trusted,
    headerTier,
    headerActive,
  });
  next();
}

/**
 * Requires an active subscription (any tier). Use for paid-only routes if you split freemium later.
 */
export function requireActiveSubscription(req, res, next) {
  if (!req.subscription?.active) {
    return res.status(402).json({
      error: "subscription_inactive",
      message: "Subscription is not active. Renew to process documents.",
    });
  }
  next();
}
