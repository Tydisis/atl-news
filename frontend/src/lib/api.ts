export type Category = 'local' | 'state' | 'national'

export interface Article {
  id: string
  title: string
  url: string
  summary: string
  source_id: string
  source_name: string
  category: Category
  published_at: string
}

export interface FeedResponse {
  count: number
  articles: Article[]
}

const BASE_URL = import.meta.env.VITE_API_URL ?? ''

export async function fetchFeed(params: { category?: Category; limit?: number } = {}): Promise<FeedResponse> {
  const qs = new URLSearchParams()
  if (params.category) qs.set('category', params.category)
  qs.set('limit', String(params.limit ?? 100))
  const res = await fetch(`${BASE_URL}/api/feed?${qs}`)
  if (!res.ok) throw new Error(`feed request failed: ${res.status}`)
  return res.json()
}

