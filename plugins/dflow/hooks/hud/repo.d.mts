// Types for repo.mjs, so the HUD mod's imports type-check.
import type { HudRepo } from '../../types'

export function repoFromPorcelain(text: string): HudRepo | null
export function repoName(remote: string | null | undefined, root: string): string
export function shortDir(cwd: string, home: string | null | undefined): string
