import express from "express";
import cors from "cors";
import helmet from "helmet";
import path from "path";
import { fileURLToPath } from "url";
import { env } from "./config/env.js";
import { subscriptionContext } from "./middleware/subscription.js";
import { extractAuth } from "./middleware/auth.js";
import { documentsRouter } from "./routes/documents.js";
// Temporarily disabled - requires Node 22 or ws package for Supabase Realtime
// import { articlesRouter } from "./routes/articles.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();

app.set("trust proxy", 1);
app.disable("x-powered-by");

// Configure Helmet security layers while leaving cross-origin asset resource pipelines unblocked
app.use(
  helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
    crossOriginOpenerPolicy: { policy: "unsafe-none" },
  }),
);

// Arm CORS globally with absolute wildcard allowances across all test environments
app.use(
  cors({
    origin: "*", 
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Subscription-Tier"],
    maxAge: 86400,
  }),
);

app.use(express.json({ limit: "1mb" }));

// Serve uploaded files so Flutter can load images as article cover art
// Files are saved to <root>/uploads/ by the documents route
const uploadsDir = path.resolve(__dirname, "../../uploads");
app.use("/uploads", express.static(uploadsDir, { maxAge: "7d" }));

app.use(subscriptionContext);
app.use(extractAuth);

const healthPayload = () => ({
  ok: true,
  service: "voxnews-node-core",
  env: env.nodeEnv,
  trustClientTierHeaders: env.trustClientTierHeaders,
});

function sendHealth(_req, res) {
  res.json(healthPayload());
}

app.get("/", (_req, res) => {
  res.json({
    ok: true,
    service: "voxnews-node-core",
    message: "GatiVani API. Deploy the Flutter web build to this domain for the UI.",
    endpoints: {
      health: "/health",
      healthUnderApi: "/api/health",
      processDocument: "POST /api/documents/process",
    },
  });
});

app.get("/health", sendHealth);
app.get("/api/health", sendHealth);

app.use("/api/documents", documentsRouter);
// Temporarily disabled - requires Node 22 or ws package for Supabase Realtime
// app.use("/api/articles", articlesRouter);

app.use((_req, res) => {
  res.status(404).json({ error: "not_found" });
});

app.listen(env.port, () => {
  console.log(`[voxnews-node-core] listening on port ${env.port}`);
});