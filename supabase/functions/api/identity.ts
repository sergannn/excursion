import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ApiError, databaseError, readBody, text } from "./http.ts";
import { profileSelect, type Row, userShape } from "./data.ts";
import { managementBody, type Operation } from "./management.ts";

export async function login(db: SupabaseClient, req: Request) {
  const body = await readBody(req);
  const email = text(body.email, "email", 190);
  if (
    typeof body.password !== "string" || !body.password.trim() ||
    body.password.length > 1024
  ) {
    throw new ApiError(422, "validation_error", "password required");
  }
  const { data: authEmail, error: resolveError } = await db.rpc(
    "resolve_auth_login_email",
    { login_value: email },
  );
  if (resolveError || typeof authEmail !== "string") {
    if (resolveError) databaseError(resolveError);
    throw new ApiError(
      401,
      "login_failed",
      "Unable to sign in with these credentials",
    );
  }
  const { data, error } = await db.auth.signInWithPassword({
    email: authEmail,
    password: body.password,
  });
  if (error || !data.session || !data.user) {
    throw new ApiError(
      error?.status === 429 ? 429 : 401,
      "login_failed",
      "Unable to sign in with these credentials",
    );
  }
  const { data: profile, error: profileError } = await db.from("profiles")
    .select(profileSelect)
    .eq("auth_user_id", data.user.id).maybeSingle();
  if (profileError || !profile) {
    await db.auth.signOut({ scope: "local" });
    if (profileError) databaseError(profileError);
    throw new ApiError(
      403,
      "profile_required",
      "Application profile is unavailable",
    );
  }
  return { token: data.session.access_token, user: userShape(profile) };
}

export async function logout(db: SupabaseClient, jwt: string) {
  // This endpoint uses the anon key plus caller JWT, never the service key.
  // admin.signOut is the SDK's stateless /logout wrapper; it does not require
  // loading a refresh token/session into this per-request client.
  const { error } = await db.auth.admin.signOut(jwt, "local");
  if (error) {
    throw new ApiError(502, "logout_failed", "Unable to revoke the session");
  }
  return { message: "Logged out successfully" };
}

export async function manageIdentity(
  db: SupabaseClient,
  caller: Row,
  req: Request,
  op: Operation,
  adminFactory: () => SupabaseClient,
) {
  // Keep this check ahead of body processing AND service-key access.
  if (caller.role_id !== 1) {
    throw new ApiError(403, "forbidden", "Administrator required");
  }
  const raw = req.body === null && op.action === "delete"
    ? {}
    : await readBody(req);
  const password = raw.password;
  delete raw.password;
  const passwordBytes = typeof password === "string"
    ? new TextEncoder().encode(password).length
    : 0;
  const hasControlCharacters = typeof password === "string" &&
    Array.from(password).some((character) => {
      const codePoint = character.codePointAt(0)!;
      return codePoint < 32 || codePoint === 127;
    });
  if (
    password !== undefined &&
    (typeof password !== "string" || password.length < 8 ||
      passwordBytes > 72 || hasControlCharacters)
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "Password needs 8+ characters (max 72 UTF-8 bytes) and no control characters",
    );
  }
  if (
    op.action === "delete" && password !== undefined ||
    op.action === "create" && password === undefined
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "Password required for create and allowed only for create/reset",
    );
  }
  const payload = managementBody(op, raw);
  const admin = adminFactory();
  const operationKey = crypto.randomUUID();
  const pendingPrepare = () =>
    new ApiError(
      503,
      "identity_operation_pending",
      `Identity operation ${operationKey} may require reconciliation; do not retry blindly`,
    );
  const { data: journal, error: prepareError } = await db.rpc(
    "begin_identity_operation",
    {
      action: op.action,
      target_id: op.id ?? null,
      payload,
      operation_key: operationKey,
    },
  );
  if (prepareError) {
    if (!/^[A-Z0-9]{5}$/.test(prepareError.code)) throw pendingPrepare();
    databaseError(prepareError);
  }
  const pending = () =>
    new ApiError(
      503,
      "identity_operation_pending",
      `Identity operation ${journal.operation_id} requires reconciliation; do not retry blindly`,
    );
  const { data: authEmail, error: authEmailError } = await db.rpc(
    "identity_auth_email",
    { operation_id: journal.operation_id },
  );
  if (authEmailError || typeof authEmail !== "string") throw pending();
  const finish = async (commit: boolean) => {
    const { error } = await db.rpc("finish_identity_operation", {
      operation_id: journal.operation_id,
      commit_change: commit,
    });
    if (error) throw pending();
  };
  // No service-role table queries or domain writes. Only Auth admin methods.
  // Definite 4xx failures compensate the staged profile. Network/5xx ambiguity
  // preserves the durable journal and denies target access for reconciliation.
  try {
    let result;
    if (op.action === "delete") {
      result = journal.auth_user_id
        ? await admin.auth.admin.deleteUser(journal.auth_user_id)
        : { error: null };
    } else if (!journal.auth_user_id) {
      if (password === undefined) {
        await finish(false);
        throw new ApiError(
          422,
          "validation_error",
          "Password required to enroll an unlinked profile",
        );
      }
      result = await admin.auth.admin.createUser({
        email: authEmail,
        password,
        email_confirm: true,
        user_metadata: {
          name: payload.name ?? journal.result.user.name,
          identity_operation: journal.operation_id,
        },
      });
    } else {
      result = await admin.auth.admin.updateUserById(journal.auth_user_id, {
        ...(payload.email !== undefined
          ? { email: authEmail, email_confirm: true }
          : {}),
        ...(payload.name !== undefined
          ? { user_metadata: { name: payload.name } }
          : {}),
        ...(password !== undefined ? { password } : {}),
      });
    }
    if (result.error) {
      if (!result.error.status || result.error.status >= 500) throw pending();
      await finish(false);
      throw new ApiError(
        result.error.status === 422 || result.error.status === 400 ? 422 : 502,
        "identity_auth_failed",
        "Auth rejected the identity change; profile change was rolled back",
      );
    }
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw pending();
  }
  await finish(true);
  return journal.result;
}

export function authAdmin(
  url: string,
  key: string,
  factory: typeof createClient,
) {
  return factory(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(15000) }),
    },
  });
}
