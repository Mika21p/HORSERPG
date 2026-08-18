import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Local browser acceptance uses isolated loopback hostnames for GM and
  // PLAYER sessions. Keep this development-only allowlist explicit.
  allowedDevOrigins: ["127.0.0.1", "127.0.0.2", "127.0.0.3", "127.0.0.4"],
};

export default nextConfig;
