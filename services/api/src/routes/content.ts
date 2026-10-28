import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type RouteContext } from '../app.ts';
import { notFound } from '../http/errors.ts';
import { parseWith, uuidParam } from '../http/validate.ts';
import {
  currentMasterCv,
  deleteDocument,
  deleteStory,
  getCvVersion,
  getDocument,
  insertStory,
  listCvVersions,
  listDocuments,
  listStories,
  saveMasterCv,
  updateDocument,
  updateStory,
} from '../repos/content.ts';

const cvBody = z.object({ markdown: z.string().max(100_000, 'Keep the CV under 100,000 characters.') }).strict();

const COMPETENCIES = ['Ownership', 'Problem solving', 'Collaboration', 'Leadership', 'Learning'] as const;
const storyField = (label: string) => z.string().trim().min(1, `Add the ${label}.`).max(4000);
const storyBody = z
  .object({
    title: z.string().trim().min(1, 'Add a title.').max(200),
    competency: z.enum(COMPETENCIES),
    situation: storyField('situation'),
    task: storyField('task'),
    action: storyField('action'),
    result: storyField('result'),
    reflection: storyField('reflection'),
  })
  .strict();

const docPatch = z
  .object({
    title: z.string().trim().min(1).max(300).optional(),
    body: z.string().max(200_000).optional(),
  })
  .strict();

export function registerContentRoutes(app: FastifyInstance, ctx: RouteContext) {
  // Master CV (versioned; every save is a new version)
  app.get('/cv/master', async (req) => {
    const auth = requireAuth(req);
    const cv = await ctx.db.forUser(auth.userId, (tx) => currentMasterCv(tx, auth.userId));
    return { cv };
  });

  app.put('/cv/master', async (req) => {
    const auth = requireAuth(req);
    const { markdown } = parseWith(cvBody, req.body);
    const cv = await ctx.db.forUser(auth.userId, async (tx) => {
      const current = await currentMasterCv(tx, auth.userId);
      if (current && current.markdown === markdown) return current;
      return saveMasterCv(tx, auth.userId, markdown, 'manual');
    });
    return { cv };
  });

  app.get('/cv/versions', async (req) => {
    const auth = requireAuth(req);
    const items = await ctx.db.forUser(auth.userId, (tx) => listCvVersions(tx, auth.userId));
    return { items };
  });

  app.get('/cv/versions/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'CV version');
    const cv = await ctx.db.forUser(auth.userId, (tx) => getCvVersion(tx, auth.userId, id));
    if (!cv) throw notFound('CV version');
    return { cv };
  });

  app.post('/cv/versions/:id/restore', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'CV version');
    const cv = await ctx.db.forUser(auth.userId, async (tx) => {
      const version = await getCvVersion(tx, auth.userId, id);
      if (!version || version.kind !== 'master') throw notFound('CV version');
      return saveMasterCv(tx, auth.userId, version.markdown, 'manual');
    });
    return { cv };
  });

  // Story bank (STAR + Reflection)
  app.get('/stories', async (req) => {
    const auth = requireAuth(req);
    const items = await ctx.db.forUser(auth.userId, (tx) => listStories(tx, auth.userId));
    return { items };
  });

  app.post('/stories', async (req, reply) => {
    const auth = requireAuth(req);
    const body = parseWith(storyBody, req.body);
    const story = await ctx.db.forUser(auth.userId, (tx) => insertStory(tx, auth.userId, body));
    reply.code(201);
    return story;
  });

  app.put('/stories/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Story');
    const body = parseWith(storyBody, req.body);
    const story = await ctx.db.forUser(auth.userId, (tx) => updateStory(tx, auth.userId, id, body));
    if (!story) throw notFound('Story');
    return story;
  });

  app.delete('/stories/:id', async (req, reply) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Story');
    const ok = await ctx.db.forUser(auth.userId, (tx) => deleteStory(tx, auth.userId, id));
    if (!ok) throw notFound('Story');
    return reply.code(204).send();
  });

  // Documents library
  app.get('/documents', async (req) => {
    const auth = requireAuth(req);
    const jobId = (req.query as { jobId?: string } | undefined)?.jobId;
    const items = await ctx.db.forUser(auth.userId, (tx) =>
      listDocuments(tx, auth.userId, jobId ? uuidParam({ jobId }, 'jobId', 'Role') : undefined),
    );
    return { items };
  });

  app.get('/documents/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Document');
    const doc = await ctx.db.forUser(auth.userId, (tx) => getDocument(tx, auth.userId, id));
    if (!doc) throw notFound('Document');
    return doc;
  });

  app.patch('/documents/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Document');
    const body = parseWith(docPatch, req.body);
    const doc = await ctx.db.forUser(auth.userId, (tx) => updateDocument(tx, auth.userId, id, body));
    if (!doc) throw notFound('Document');
    return doc;
  });

  app.delete('/documents/:id', async (req, reply) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Document');
    const ok = await ctx.db.forUser(auth.userId, (tx) => deleteDocument(tx, auth.userId, id));
    if (!ok) throw notFound('Document');
    return reply.code(204).send();
  });
}
