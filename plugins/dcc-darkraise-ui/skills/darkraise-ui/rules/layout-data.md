# Layout & data

## Use `SidebarLayout`, not a hand-built shell

The kit ships the whole application shell: collapsible sidebar, nav groups,
header slot, user menu, search command, notification bell, theme switcher.

**Incorrect**

```tsx
<div className="flex h-screen">
  <aside className="w-64 border-r bg-card">
    <ul>{items.map((i) => <li key={i.href}><a href={i.href}>{i.label}</a></li>)}</ul>
  </aside>
  <main className="flex-1 overflow-auto p-6">{children}</main>
</div>
```

**Correct**

```tsx
import { SidebarLayout, type NavGroup } from "darkraise-ui/layout"
import { LayoutDashboard, Settings } from "lucide-react"

const nav: NavGroup[] = [
  {
    label: "Workspace",
    items: [
      { label: "Overview", href: "/", icon: LayoutDashboard },
      { label: "Settings", href: "/settings", icon: Settings, badge: "New" },
    ],
  },
]

<SidebarLayout
  nav={nav}
  user={user}
  onLogout={logout}
  showThemeSwitcher
>
  {children}
</SidebarLayout>
```

`NavItem` is `{ label, href, icon?, badge?, children? }` — `children` nests a
sub-navigation. `icon` is a Lucide icon component, passed as the component itself,
not a string.

## `PageHeader` for the page's own chrome

**Correct**

```tsx
import { PageHeader } from "darkraise-ui/layout"

<PageHeader
  breadcrumbs={[{ label: "Workspace", href: "/" }, { label: "Settings" }]}
  title="Settings"
  description="Manage your workspace."
  actions={<Button>Save</Button>}
  tabs={tabs}
/>
```

Do not rebuild breadcrumbs, a title block, or a tab strip by hand — `PageHeader`
carries the theme's spacing and type scale for all four.

## The kit is router-agnostic by construction

**No component in the kit imports a router.** That is why it works with TanStack
Router, React Router, or anything else. You supply an adapter once.

**Incorrect**

```tsx
// Expecting SidebarLayout to know about your router.
<SidebarLayout nav={nav}>{children}</SidebarLayout>
// …with no RouterAdapterProvider mounted. Links will not navigate correctly.
```

**Correct**

```tsx
import { RouterAdapterProvider, type RouterAdapter } from "darkraise-ui/router"

const adapter: RouterAdapter = {
  Link,                  // ComponentType<RouterLinkProps>
  useNavigate: () => { const n = useNavigate(); return (to) => n({ to }) },
  usePathname: () => useRouterState({ select: (s) => s.location.pathname }),
  useBack: () => { const r = useRouter(); return () => r.history.back() },
  useInvalidate: () => { const r = useRouter(); return () => r.invalidate() },
}

<RouterAdapterProvider value={adapter}>{children}</RouterAdapterProvider>
```

The adapter's `Link` receives `RouterLinkProps`: `to`, `className`,
`activeClassName`, `activeExact`, `style`, `children`, `onClick`. Read
`dist/router/index.d.ts` before writing an adapter for a different router.

## Use `DataTable`, not a hand-built table

**Incorrect**

```tsx
<table>
  <thead>{/* manual sort handlers */}</thead>
  <tbody>{rows.map(...)}</tbody>
</table>
```

**Correct**

```tsx
import { DataTable, ColumnHeader, RowActions } from "darkraise-ui/data-table"

const columns: ColumnDef<Deployment>[] = [
  {
    accessorKey: "name",
    header: ({ column }) => <ColumnHeader column={column} title="Name" />,
  },
  {
    id: "actions",
    cell: ({ row }) => (
      <RowActions actions={[{ label: "Delete", onSelect: () => remove(row.original.id) }]} />
    ),
  },
]

<DataTable
  columns={columns}
  data={data}
  isLoading={isLoading}
  searchKey="name"
  searchPlaceholder="Search deployments…"
  facets={["status"]}
/>
```

`DataTableProps` is `{ columns, data, isLoading?, searchKey?, searchPlaceholder?,
facets?, virtualize? }`. `facets` takes **column ids** to offer as multi-select
filters. `virtualize` windows long lists instead of paginating them.

The module also ships `DataTableSkeleton` (loading), `DataTableEmpty` (no rows),
`DataTableFacet`, and `exportToCsv`. Use them rather than building equivalents.

## The provider stack order is load-bearing

Wrong order fails subtly rather than loudly — a theme that does not apply inside a
portal, a toast that renders unthemed, a floating panel that cannot navigate.

**Correct — outermost first**

```tsx
export function AppProviders({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider config={themeConfig}>
        <RouterAdapterProvider value={routerAdapter}>
          <FloatingPanelProvider>
            {children}
            <FloatingPanelHost />
            <Toaster />
          </FloatingPanelProvider>
        </RouterAdapterProvider>
      </ThemeProvider>
    </QueryClientProvider>
  )
}
```

`FloatingPanelHost` and `Toaster` are **siblings of `children`, inside
`FloatingPanelProvider`** — not wrappers, and not outside it. Both render into the
themed tree, which is why they sit below `ThemeProvider`.

## Error pages come from the kit

**Incorrect**

```tsx
const router = createRouter({ routeTree })   // default framework error screens
```

**Correct**

```tsx
import { NotFoundPage, ErrorPage } from "darkraise-ui/errors"

const router = createRouter({
  routeTree,
  defaultNotFoundComponent: NotFoundPage,
  defaultErrorComponent: ErrorPage,
})
```

`darkraise-ui/errors` also ships `ServerErrorPage`, `MaintenancePage`, and
`ErrorLayout` for building your own with the kit's framing.
