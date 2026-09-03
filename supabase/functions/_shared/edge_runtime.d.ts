// Supabase's Edge runtime exposes an `EdgeRuntime` global for background work
// that outlives the response. Its own edge-runtime.d.ts ships the declaration,
// but importing that module does not register the ambient global with
// `deno check`, so the typecheck reports EdgeRuntime as undefined. Declare the
// one member we call; the runtime provides the rest.
declare namespace EdgeRuntime {
  function waitUntil<T>(promise: Promise<T>): Promise<T>;
}
