import { useCallback, useEffect, useState } from 'react'
import { ExternalLink, RefreshCw } from 'lucide-react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { fetchFeed, type Article, type Category } from '@/lib/api'
import { relativeTime, stripHtml } from '@/lib/format'

type Tab = 'all' | Category

const TABS: { value: Tab; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'local', label: 'Local' },
  { value: 'state', label: 'Georgia' },
  { value: 'national', label: 'National' },
]

const CATEGORY_BADGE: Record<Category, string> = {
  local: 'bg-blue-100 text-blue-900 dark:bg-blue-900/40 dark:text-blue-200',
  state: 'bg-amber-100 text-amber-900 dark:bg-amber-900/40 dark:text-amber-200',
  national: 'bg-rose-100 text-rose-900 dark:bg-rose-900/40 dark:text-rose-200',
}

function ArticleCard({ article }: { article: Article }) {
  const summary = stripHtml(article.summary)
  return (
    <Card className="flex flex-col">
      <CardHeader>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Badge variant="secondary" className={CATEGORY_BADGE[article.category]}>
            {article.category}
          </Badge>
          <span>{article.source_name}</span>
          <span>·</span>
          <span>{relativeTime(article.published_at)}</span>
        </div>
        <CardTitle className="pt-2">
          <a
            href={article.url}
            target="_blank"
            rel="noopener noreferrer"
            className="hover:underline"
          >
            {article.title}
          </a>
        </CardTitle>
      </CardHeader>
      {summary && (
        <CardContent className="text-sm text-muted-foreground line-clamp-3">{summary}</CardContent>
      )}
      <CardFooter className="mt-auto">
        <a
          href={article.url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-sm font-medium hover:underline"
        >
          Read at {article.source_name}
          <ExternalLink className="h-3.5 w-3.5" />
        </a>
      </CardFooter>
    </Card>
  )
}

export default function App() {
  const [tab, setTab] = useState<Tab>('all')
  const [articles, setArticles] = useState<Article[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async (current: Tab) => {
    setLoading(true)
    setError(null)
    try {
      const params = current === 'all' ? {} : { category: current }
      const data = await fetchFeed({ ...params, limit: 100 })
      setArticles(data.articles)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'failed to load feed')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load(tab)
  }, [tab, load])

  const onRefresh = async () => {
    setRefreshing(true)
    try {
      await load(tab)
    } finally {
      setRefreshing(false)
    }
  }

  return (
    <div className="min-h-screen bg-background">
      <header className="border-b">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-5">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">ATL News</h1>
            <p className="text-sm text-muted-foreground">
              Atlanta · Georgia politics · US politics
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={onRefresh} disabled={refreshing}>
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-6">
        <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
          <TabsList>
            {TABS.map((t) => (
              <TabsTrigger key={t.value} value={t.value}>
                {t.label}
              </TabsTrigger>
            ))}
          </TabsList>

          {TABS.map((t) => (
            <TabsContent key={t.value} value={t.value}>
              {error && (
                <div className="rounded-md border border-destructive/50 bg-destructive/10 p-4 text-sm text-destructive">
                  {error}
                </div>
              )}
              {loading ? (
                <div className="py-12 text-center text-muted-foreground">Loading…</div>
              ) : articles.length === 0 ? (
                <div className="py-12 text-center text-muted-foreground">No articles yet.</div>
              ) : (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  {articles.map((a) => (
                    <ArticleCard key={a.id} article={a} />
                  ))}
                </div>
              )}
            </TabsContent>
          ))}
        </Tabs>
      </main>
    </div>
  )
}
