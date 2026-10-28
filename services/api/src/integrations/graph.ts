/** Minimal Microsoft Graph client for deleting a customer identity on account deletion. */
export type GraphConfig = { tenantId: string; clientId: string; clientSecret: string };

export function createGraphClient(cfg: GraphConfig) {
  let cached: { token: string; expires: number } | null = null;

  async function token(): Promise<string> {
    if (cached && cached.expires > Date.now() + 60_000) return cached.token;
    const res = await fetch(`https://login.microsoftonline.com/${encodeURIComponent(cfg.tenantId)}/oauth2/v2.0/token`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
        grant_type: 'client_credentials',
        scope: 'https://graph.microsoft.com/.default',
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new Error(`Graph token request failed: HTTP ${res.status}`);
    const body = (await res.json()) as { access_token: string; expires_in: number };
    cached = { token: body.access_token, expires: Date.now() + body.expires_in * 1000 };
    return cached.token;
  }

  return {
    async deleteUser(oid: string): Promise<void> {
      const res = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(oid)}`, {
        method: 'DELETE',
        headers: { authorization: `Bearer ${await token()}` },
        signal: AbortSignal.timeout(10_000),
      });
      if (res.status !== 204 && res.status !== 404) throw new Error(`Graph user deletion failed: HTTP ${res.status}`);
    },
  };
}

export type GraphClient = ReturnType<typeof createGraphClient>;
