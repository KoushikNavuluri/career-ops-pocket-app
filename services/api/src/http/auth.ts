/** Entra External ID access-token verification (issuer, audience, signature, scope). */
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export type Claims = { oid: string; email?: string; name?: string; roles: string[] };
export type TokenVerifier = (token: string) => Promise<Claims>;

export function createVerifier(opts: { keys: JWTVerifyGetKey; issuer: string; audience: string; requiredScope: string }): TokenVerifier {
  return async (token: string) => {
    const { payload } = await jwtVerify(token, opts.keys, {
      issuer: opts.issuer,
      audience: opts.audience,
      algorithms: ['RS256'],
      clockTolerance: 60,
    });
    const scopes = typeof payload.scp === 'string' ? payload.scp.split(' ') : [];
    if (!scopes.includes(opts.requiredScope)) throw new Error('missing scope');
    const oid = typeof payload.oid === 'string' ? payload.oid : typeof payload.sub === 'string' ? payload.sub : '';
    if (!oid) throw new Error('missing subject');
    const email =
      typeof payload.email === 'string'
        ? payload.email
        : typeof payload.preferred_username === 'string' && payload.preferred_username.includes('@')
          ? payload.preferred_username
          : undefined;
    return {
      oid,
      email,
      name: typeof payload.name === 'string' ? payload.name : undefined,
      roles: Array.isArray(payload.roles) ? payload.roles.filter((r): r is string => typeof r === 'string') : [],
    };
  };
}

/** Reads issuer and JWKS location from the tenant's OpenID configuration. */
export async function createVerifierFromDiscovery(discoveryUrl: string, audience: string, requiredScope: string): Promise<TokenVerifier> {
  const res = await fetch(discoveryUrl, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`OpenID discovery failed with HTTP ${res.status}`);
  const doc = (await res.json()) as { issuer?: string; jwks_uri?: string };
  if (!doc.issuer || !doc.jwks_uri) throw new Error('OpenID discovery document is missing issuer or jwks_uri');
  const keys = createRemoteJWKSet(new URL(doc.jwks_uri), { cooldownDuration: 30_000, cacheMaxAge: 6 * 60 * 60 * 1000 });
  return createVerifier({ keys, issuer: doc.issuer, audience, requiredScope });
}
