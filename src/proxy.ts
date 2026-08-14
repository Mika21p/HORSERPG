import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

function getSupabaseEnvironment() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !publishableKey) {
    throw new Error("Missing browser-safe Supabase environment variables.");
  }

  return { url, publishableKey };
}

function redirectWithSessionCookies(
  response: NextResponse,
  destination: URL,
) {
  const redirectResponse = NextResponse.redirect(destination);
  response.cookies
    .getAll()
    .forEach((cookie) => redirectResponse.cookies.set(cookie));
  return redirectResponse;
}

/**
 * Refreshes Supabase Auth cookies before rendering and provides an optimistic
 * route-level guard. Pages and Server Actions repeat authorization checks.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, publishableKey } = getSupabaseEnvironment();

  const supabase = createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
        Object.entries(headers).forEach(([key, value]) =>
          response.headers.set(key, value),
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { pathname } = request.nextUrl;

  if (!user) {
    if (pathname === "/login") {
      return response;
    }

    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", pathname);
    return redirectWithSessionCookies(response, loginUrl);
  }

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  const isGM = profile?.role === "GM";

  if (pathname === "/login") {
    return redirectWithSessionCookies(
      response,
      new URL(isGM ? "/admin" : "/", request.url),
    );
  }

  if (pathname === "/admin" || pathname.startsWith("/admin/")) {
    if (!isGM) {
      return redirectWithSessionCookies(response, new URL("/", request.url));
    }
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
