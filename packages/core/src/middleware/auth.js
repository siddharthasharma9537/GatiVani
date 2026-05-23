/**
 * Authentication Middleware
 *
 * Extracts and verifies JWT tokens from Authorization headers.
 * Decodes JWT payload to extract user ID without external verification
 * (suitable for development; production should use Supabase JWT verification).
 *
 * Usage:
 *   app.use(requireAuth);
 *   // req.userId and req.user will be populated if valid JWT present
 */

/**
 * Extracts and decodes JWT from Authorization header
 * Format: "Bearer <token>"
 *
 * @param {string} token - JWT token string
 * @returns {Object|null} Decoded payload or null if invalid
 */
function decodeJWT(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const payload = parts[1];
    const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf-8'));
    return decoded;
  } catch (err) {
    return null;
  }
}

/**
 * Middleware: Extracts userId from JWT in Authorization header
 * Attaches userId to req for use in route handlers
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
export function extractAuth(req, res, next) {
  const authHeader = req.get('Authorization') || '';
  const match = authHeader.match(/^Bearer\s+(.+)$/);

  if (!match) {
    req.userId = null;
    req.user = null;
    return next();
  }

  const token = match[1];
  const decoded = decodeJWT(token);

  if (decoded && decoded.sub) {
    req.userId = decoded.sub;
    req.user = decoded;
  } else {
    req.userId = null;
    req.user = null;
  }

  next();
}

/**
 * Middleware: Requires valid authentication (userId must be present)
 * Returns 401 Unauthorized if no valid JWT provided
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
export function requireAuth(req, res, next) {
  // First extract auth if not already done
  if (!req.userId) {
    extractAuth(req, res, () => {});
  }

  if (!req.userId) {
    return res.status(401).json({
      error: 'unauthorized',
      message: 'Valid JWT token required in Authorization header (Bearer <token>)'
    });
  }

  next();
}

/**
 * Middleware: Combines extractAuth + requireAuth
 * Always extracts, but also requires presence
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
export function authRequired(req, res, next) {
  extractAuth(req, res, () => {
    if (!req.userId) {
      return res.status(401).json({
        error: 'unauthorized',
        message: 'Valid JWT token required in Authorization header (Bearer <token>)'
      });
    }
    next();
  });
}
