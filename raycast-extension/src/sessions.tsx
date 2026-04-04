import { List, ActionPanel, Action, showToast, Toast, Icon } from "@raycast/api";
import { useState, useEffect } from "react";
import {
  discoverServer,
  fetchSessions,
  timeAgo,
  abbreviateHome,
  type DiscoveredServer,
  type Session,
} from "./opencode";

export default function SessionsCommand() {
  const [server, setServer] = useState<DiscoveredServer | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function init() {
      const found = discoverServer();
      if (!found) {
        await showToast({
          style: Toast.Style.Failure,
          title: "OpenCode Desktop not running",
          message: "Start OpenCode Desktop first",
        });
        setIsLoading(false);
        return;
      }
      setServer(found);
      const fetched = await fetchSessions(found);
      setSessions(fetched);
      setIsLoading(false);
    }
    init();
  }, []);

  // Group sessions by directory
  const grouped = new Map<string, Session[]>();
  for (const s of sessions) {
    const dir = s.directory ? abbreviateHome(s.directory) : "Unknown";
    const existing = grouped.get(dir) || [];
    existing.push(s);
    grouped.set(dir, existing);
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter sessions...">
      {sessions.length === 0 && !isLoading && (
        <List.EmptyView
          title={server ? "No Sessions" : "OpenCode Desktop Not Running"}
          description={server ? "Start a new session from the Dispatch command" : "Start OpenCode Desktop first"}
          icon={server ? Icon.Message : Icon.ExclamationMark}
        />
      )}

      {Array.from(grouped.entries()).map(([dir, dirSessions]) => (
        <List.Section key={dir} title={dir}>
          {dirSessions.map((s) => (
            <List.Item
              key={s.id}
              title={s.name}
              subtitle={s.id.slice(0, 8)}
              accessories={[{ text: timeAgo(s.updatedAt) }]}
              icon={Icon.Message}
              actions={
                <ActionPanel>
                  <Action.CopyToClipboard
                    title="Copy Session ID"
                    content={s.id}
                  />
                </ActionPanel>
              }
            />
          ))}
        </List.Section>
      ))}
    </List>
  );
}
