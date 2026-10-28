import { createClient } from "@supabase/supabase-js";
import { PDFDocument } from "pdf-lib";
import { createHandler } from "./index.ts";
import { renderTickets, ticketIds } from "./ticket.ts";
import { type Row } from "./data.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(a: unknown, b: unknown) {
  assert(
    JSON.stringify(a) === JSON.stringify(b),
    `${JSON.stringify(a)} != ${JSON.stringify(b)}`,
  );
}
const secret = "fixture-service-key";
const password = "StrongPassword1!";
function fixture(
  options: {
    role?: number;
    badJwt?: boolean;
    noProfile?: boolean;
    authStatus?: number;
    finishFails?: boolean;
    prepareFails?: boolean;
    unlinked?: boolean;
    missingKey?: boolean;
    loginFails?: boolean;
    logoutFails?: boolean;
  } = {},
) {
  const calls: {
    path: string;
    method: string;
    key: string | null;
    authorization: string | null;
    body: Row | null;
  }[] = [];
  const envReads: string[] = [];
  const caller = {
    id: 1,
    name: "Admin",
    email: "admin@test.local",
    role_id: options.role ?? 1,
  };
  const target = { id: 8, name: "Иван", email: "ivan@test.local", role_id: 2 };
  const transport: typeof fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    const rawBody = await req.text();
    const body = rawBody ? JSON.parse(rawBody) : null;
    calls.push({
      path: url.pathname,
      method: req.method,
      key: req.headers.get("apikey"),
      authorization: req.headers.get("authorization"),
      body,
    });
    const json = (data: unknown, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (url.pathname === "/auth/v1/user") {
      return options.badJwt
        ? json({ message: "invalid" }, 401)
        : json({ id: "caller-auth", email: caller.email });
    }
    if (url.pathname === "/auth/v1/token") {
      return options.loginFails
        ? json({ message: "credentials rejected" }, 400)
        : json({
          access_token: "new-jwt",
          refresh_token: "never-return-this",
          token_type: "bearer",
          expires_in: 3600,
          user: { id: "caller-auth", email: caller.email },
        });
    }
    if (url.pathname.endsWith("/resolve_auth_login_email")) {
      return json(caller.email);
    }
    if (url.pathname === "/auth/v1/logout") {
      return options.logoutFails
        ? json({ message: "failure" }, 500)
        : new Response(null, { status: 204 });
    }
    if (url.pathname === "/rest/v1/profiles") {
      return json(options.noProfile ? [] : [caller]);
    }
    if (url.pathname.endsWith("/begin_identity_operation")) {
      return options.prepareFails
        ? json({ code: "42501", message: "denied" }, 403)
        : json({
          operation_id: "journal-uuid",
          target_id: 8,
          auth_user_id: options.unlinked
            ? null
            : "22222222-2222-4222-8222-222222222222",
          result: { message: "Saved", user: target },
        });
    }
    if (url.pathname.endsWith("/identity_auth_email")) {
      return json(target.email);
    }
    if (url.pathname.endsWith("/finish_identity_operation")) {
      return options.finishFails
        ? json({ code: "23514", message: "do not expose SQL" }, 400)
        : json({ message: "Done" });
    }
    if (url.pathname.startsWith("/auth/v1/admin/users")) {
      return options.authStatus
        ? json(
          { msg: `never expose ${password} ${secret}` },
          options.authStatus,
        )
        : json({ user: { id: "target-auth", email: target.email } });
    }
    throw new Error(`Unexpected request ${req.method} ${url.pathname}`);
  };
  const handler = createHandler({
    env: (name) => {
      envReads.push(name);
      return ({
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_ANON_KEY: "anon",
        SUPABASE_SERVICE_ROLE_KEY: options.missingKey ? undefined : secret,
      } as Record<string, string | undefined>)[name];
    },
    client: (url, key, opts) =>
      createClient(url, key, {
        ...opts,
        global: { ...opts?.global, fetch: transport },
      }),
  });
  const request = async (
    path: string,
    method = "POST",
    body: unknown = {},
    auth = true,
  ) => {
    const response = await handler(
      new Request(`https://local.test/api${path}`, {
        method,
        headers: {
          "content-type": "application/json",
          ...(auth
            ? { authorization: "Bearer caller-jwt", apikey: "attacker-key" }
            : {}),
        },
        body: JSON.stringify(body),
      }),
    );
    const data = await response.json();
    assert(!JSON.stringify(data).includes(secret));
    assert(!JSON.stringify(data).includes(password));
    return { response, data };
  };
  return { calls, envReads, request };
}

Deno.test("login returns legacy token/user with no refresh token or credentials", async () => {
  const f = fixture();
  const r = await f.request("/auth/login", "POST", {
    email: "admin@test.local",
    password,
  }, false);
  equal(r.response.status, 200);
  equal(Object.keys(r.data).sort(), ["token", "user"]);
  equal(r.data.token, "new-jwt");
  equal(r.data.user.id, 1);
  assert(!f.envReads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  equal(
    (await fixture({ loginFails: true }).request("/auth/login", "POST", {
      email: "x@y.test",
      password,
    }, false)).response.status,
    401,
  );
  const missing = fixture({ noProfile: true });
  equal(
    (await missing.request("/auth/login", "POST", {
      email: "x@y.test",
      password,
    }, false)).response.status,
    403,
  );
  assert(missing.calls.some((c) => c.path === "/auth/v1/logout"));
});
Deno.test("logout revokes current session with anon key and caller JWT", async () => {
  const f = fixture();
  equal((await f.request("/auth/logout")).response.status, 200);
  const c = f.calls.find((c) => c.path === "/auth/v1/logout")!;
  equal(c.key, "anon");
  equal(c.authorization, "Bearer caller-jwt");
  assert(!f.envReads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  equal(
    (await fixture({ logoutFails: true }).request("/auth/logout")).response
      .status,
    502,
  );
});
for (const method of ["POST", "PUT", "DELETE"]) {
  Deno.test(`identity ${method} rejects nonadmin, invalid JWT and unlinked caller before reading service key`, async () => {
    for (
      const options of [{ role: 2 }, { badJwt: true }, { noProfile: true }]
    ) {
      const f = fixture(options);
      const r = await f.request(
        method === "POST" ? "/users" : "/users/8",
        method,
        { name: "Иван", email: "ivan@test.local", role_id: 2, password },
      );
      assert([401, 403].includes(r.response.status));
      assert(!f.envReads.includes("SUPABASE_SERVICE_ROLE_KEY"));
      assert(!f.calls.some((c) => c.key === secret));
    }
  });
  Deno.test(`identity ${method} limits service role to Auth admin and preserves numeric ID`, async () => {
    const f = fixture({ unlinked: method === "POST" });
    const r = await f.request(
      method === "POST" ? "/users" : "/users/8",
      method,
      method === "DELETE"
        ? {}
        : { name: "Иван", email: "ivan@test.local", role_id: 2, password },
    );
    equal(r.response.status, method === "POST" ? 201 : 200);
    equal(r.data.user.id, 8);
    const privileged = f.calls.filter((c) => c.key === secret);
    equal(privileged.length, 1);
    assert(privileged.every((c) => c.path.startsWith("/auth/v1/admin/users")));
    const prepare = f.calls.find((c) =>
      c.path.endsWith("/begin_identity_operation")
    )!;
    equal(prepare.key, "anon");
    equal(prepare.authorization, "Bearer caller-jwt");
    assert(!("password" in prepare.body!.payload));
    equal(f.calls.at(-1)!.body!.commit_change, true);
  });
}
Deno.test("invalid passwords and unsupported fields fail before service key or journal", async () => {
  for (
    const value of [
      undefined,
      null,
      "",
      "short",
      "valid123\n",
      "a".repeat(73),
    ]
  ) {
    const f = fixture();
    equal(
      (await f.request("/users", "POST", {
        name: "User",
        email: "u@test.local",
        role_id: 2,
        password: value,
      })).response.status,
      422,
    );
    assert(!f.envReads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  }
  for (const value of ["abcdefgh", "        ", "старый12"]) {
    const f = fixture();
    equal(
      (await f.request("/users", "POST", {
        name: "User",
        email: "u@test.local",
        role_id: 2,
        password: value,
      })).response.status,
      201,
    );
  }
  for (
    const extra of [{ auth_user_id: "forged" }, { service_role_key: secret }, {
      password_confirmation: password,
    }]
  ) {
    const f = fixture();
    equal(
      (await f.request("/users", "POST", {
        name: "User",
        email: "u@test.local",
        role_id: 2,
        password,
        ...extra,
      })).response.status,
      422,
    );
  }
  equal(
    (await fixture().request("/users/8", "DELETE", { password })).response
      .status,
    422,
  );
});
Deno.test("definite Auth failure compensates; ambiguous/commit failures remain explicit and pending", async () => {
  const rejected = fixture({ authStatus: 422 });
  const r = await rejected.request("/users/8", "PUT", {
    email: "new@test.local",
  });
  equal(r.response.status, 422);
  equal(rejected.calls.at(-1)!.body!.commit_change, false);
  for (
    const options of [{ authStatus: 500 }, { finishFails: true }, {
      authStatus: 422,
      finishFails: true,
    }]
  ) {
    const f = fixture(options);
    const result = await f.request("/users/8", "PUT", { password });
    equal(result.response.status, 503);
    equal(result.data.error.code, "identity_operation_pending");
    assert(result.data.message.includes("journal-uuid"));
    if (options.authStatus === 500) {
      assert(
        !f.calls.some((c) => c.path.endsWith("/finish_identity_operation")),
      );
    }
  }
  const denied = fixture({ prepareFails: true });
  equal(
    (await denied.request("/users/8", "PUT", { password })).response.status,
    403,
  );
  assert(!denied.calls.some((c) => c.path.includes("/auth/v1/admin")));
  const missing = fixture({ missingKey: true });
  equal(
    (await missing.request("/users/8", "PUT", { password })).response.status,
    503,
  );
  assert(
    !missing.calls.some((c) => c.path.endsWith("/begin_identity_operation")),
  );
});
Deno.test("unlinked profile enrollment requires password; deletion can finalize without Auth", async () => {
  const f = fixture({ unlinked: true });
  equal(
    (await f.request("/users/8", "PUT", { name: "Updated" })).response.status,
    422,
  );
  equal(f.calls.at(-1)!.body!.commit_change, false);
  const d = fixture({ unlinked: true });
  equal((await d.request("/users/8", "DELETE")).response.status, 200);
  assert(!d.calls.some((c) => c.path.includes("/auth/v1/admin")));
});
Deno.test("ticket IDs support Flutter arrays, validate all IDs and bound PDF work", () => {
  equal(ticketIds(9, new URLSearchParams("ids[]=9&ids[]=10&ids[]=9")), [9, 10]);
  equal(ticketIds(9, new URLSearchParams("ids[0]=10&ids[1]=11")), [10, 11]);
  equal(ticketIds(9, new URLSearchParams()), [9]);
  for (
    const query of [
      "ids[]=",
      "ids[]=1,2",
      "ids[x]=9",
      "ids[]=0",
      Array(101).fill("ids[]=9").join("&"),
    ]
  ) {
    let failed = false;
    try {
      ticketIds(9, new URLSearchParams(query));
    } catch {
      failed = true;
    }
    assert(failed);
  }
});
Deno.test("PDF embeds Cyrillic TrueType font and groups selected seats in one ticket", async () => {
  const b = {
    id: 9,
    excursion: { title: "Экскурсия в Ялту" },
    excursion_date: "2026-10-28",
    time: "12:00:00",
    stop: { name: "Симферополь" },
    bus_seat: { seat_number: 3 },
    customer_name: "Иван Иванов",
    customer_phone: "123",
    price: 100,
    debt: 20,
    passenger_type: "adult",
  };
  const bytes = await renderTickets([b, {
    ...b,
    id: 10,
    customer_name: "Я".repeat(600),
  }]);
  equal(new TextDecoder().decode(bytes.slice(0, 5)), "%PDF-");
  const pdf = await PDFDocument.load(bytes);
  equal(pdf.getPageCount(), 1);
  equal(pdf.getTitle(), "Электронные билеты");
  const objects = pdf.context.enumerateIndirectObjects().map(([, o]) =>
    o.toString()
  ).join("\n");
  assert(objects.includes("/FontFile2"));
  assert(objects.includes("/ToUnicode"));
});
