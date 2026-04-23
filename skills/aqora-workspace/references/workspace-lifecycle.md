# Workspace Lifecycle

An aqora workspace has two runner slots: `editor` (read-write pair programming) and `viewer` (read-only spectating). Each slot is either live (has a non-null `url` and a `command` of `EDIT` or `RUN`) or cold (both `url` and `command` are null).

| State | Meaning | Executable? |
| :---- | :------ | :---------- |
| `editor_url` present | An editor kernel is live for the current user. | Yes, this is the URL the execute script targets. |
| `viewer_url` present, `editor_url` null | Only a read-only viewer exists. | No. Execution needs the editor. |
| Both null | No runner is alive. | No. Start the workspace from the aqora UI first. |

`list-workspaces.sh --url-only` prefers the editor URL, falls back to the viewer URL, and exits non-zero if both are null. `execute-code.sh --workspace ID` relies on this: if there is no editor URL, it will not have a kernel to talk to.

## Idle Shutdown

Workspaces shut down after a period of inactivity. The exact window depends on the user's plan. For long multi-step work, either send a lightweight keep-alive call every few minutes or expect to coordinate a restart with the user.

## Starting a Workspace

If the target workspace has no live runner, direct the user to start it from the aqora UI rather than trying to start it programmatically. The UI handles billing, resource quotas, and image selection that the scripts do not.

## Mid-Session Restarts

If a workspace is restarted while execution is in flight (manual restart, platform operation, idle shutdown), the call fails and kernel state is lost. Re-run `list-workspaces.sh` to confirm the runner is still live before assuming the failure was a code bug.

## Multiple Runners at Once

A workspace can have both an editor runner and a viewer runner live simultaneously. This is the normal state when the owner is editing while a collaborator watches. The scripts default to the editor because that is where cell mutations take effect. If you need to observe without risk of mutation, you can target the viewer URL explicitly with `execute-code.sh --url <viewer_url>`.

## Session IDs

A workspace may host multiple browser tabs for the same runner. Pass `--session SID` to target a specific one. Without a session id, execution targets the runner's default scratchpad. The scratchpad does not collide with user sessions, but it also does not persist cell outputs in the UI. Use the scratchpad for introspection and validation. Use a session id when you need to create cells that the user will see and interact with.
