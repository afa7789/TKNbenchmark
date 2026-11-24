import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { proofSuite } from '../proofs.mjs'

const here = dirname(fileURLToPath(import.meta.url))

// The proof suite is the same before and after: compile, no escape hatches, statements unchanged.
export const visible = (lang) => proofSuite(here, 'ISort', lang)
export const hidden = visible
