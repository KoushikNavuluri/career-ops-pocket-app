import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanDescription, csvEscape, jobsToCsv, normalizeCompany } from '../../src/domain/jobs.ts';

test('normalizeCompany strips legal suffixes and punctuation', () => {
  assert.equal(normalizeCompany('Acme, Inc.'), 'acme');
  assert.equal(normalizeCompany('ACME Pvt. Ltd'), 'acme');
});

test('csvEscape quotes and blocks formula injection', () => {
  assert.equal(csvEscape('a,b'), '"a,b"');
  assert.equal(csvEscape('=HYPERLINK("x")'), `"'=HYPERLINK(""x"")"`);
  assert.equal(csvEscape(null), '');
});

test('jobsToCsv leaves Inbox score blank', () => {
  const csv = jobsToCsv([
    { company: 'A', role: 'R', status: 'Inbox', score: 3, salary_text: null, location: null, created_at: '2026-10-01T00:00:00Z' },
    { company: 'B', role: 'S', status: 'Evaluated', score: 4.5, salary_text: '₹40L', location: 'Remote', created_at: '2026-10-02T00:00:00Z' },
  ]);
  const lines = csv.trim().split('\n');
  assert.equal(lines[0], 'Company,Role,Status,Score,Salary,Location,Date');
  assert.equal(lines[1], 'A,R,Inbox,,,,2026-10-01');
  assert.equal(lines[2], 'B,S,Evaluated,4.5,₹40L,Remote,2026-10-02');
});

test('cleanDescription normalises whitespace', () => {
  assert.equal(cleanDescription('a\r\n\r\n\r\n\r\nb\t c'), 'a\n\nb c');
});
