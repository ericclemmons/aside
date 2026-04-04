import { List, ActionPanel, Action, Detail, Icon } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { discoverServer, fetchSessions, timeAgo, abbreviateHome } from "./opencode";

export default function SessionsCommand() {
  const {
    data: sessions,
    isLoading,
    error,
  } = usePromise(async () => {
    const server = discoverServer();
    if (!server) throw new Error("OpenCode Desktop is not running. Start it first.");
    return fetchSessions(server);
  });

  if (error) {
    return (
      <Detail
        markdown={`## OpenCode Desktop Not Found\n\n${error.message}`}
        actions={
          <ActionPanel>
            <Action.OpenInBrowser title="Get OpenCode Desktop" url="https://opencode.ai" />
          </ActionPanel>
        }
      />
    );
  }

  // Group sessions by directory
  const grouped = new Map<string, typeof sessions>();
  for (const s of sessions ?? []) {
    const dir = s.directory ? abbreviateHome(s.directory) : "Unknown";
    const existing = grouped.get(dir) ?? [];
    existing.push(s);
    grouped.set(dir, existing);
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter sessions...">
      {(sessions ?? []).length === 0 && !isLoading && (
        <List.EmptyView
          title="No Sessions"
          description="Start a new session from the Dispatch command"
          icon={Icon.Message}
        />
      )}

      {Array.from(grouped.entries()).map(([dir, dirSessions]) => (
        <List.Section key={dir} title={dir}>
          {(dirSessions ?? []).map((s) => (
            <List.Item
              key={s.id}
              title={s.name}
              subtitle={s.id.slice(0, 8)}
              accessories={[{ text: timeAgo(s.updatedAt) }]}
              icon={Icon.Message}
              actions={
                <ActionPanel>
                  <Action.CopyToClipboard title="Copy Session ID" content={s.id} />
                </ActionPanel>
              }
            />
          ))}
        </List.Section>
      ))}
    </List>
  );
}
