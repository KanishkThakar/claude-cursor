# Background Chrome work

Use this path when the user wants their own mouse and keyboard left alone. It applies to browser tasks in Claude Code, including local Claude Desktop Code sessions when the Chrome integration is available. Do not infer tool availability from this file.

## Select and connect the real browser controller

Read the installed `chrome-browser` skill before using Claude in Chrome. Discover the current schemas, including deferred tools, and load the tools needed for the task together. The installed Anthropic skill describes `mcp__claude-in-chrome__*`; some sessions expose an enable tool first. Use only tools actually offered, and respect their enablement and site approvals.

Typical capabilities, when present:

| Capability | Relevant discovered tool |
| --- | --- |
| Current session and tab IDs | `tabs_context_mcp` |
| A separate work tab | `tabs_create_mcp` |
| Navigation scoped to a tab | `navigate` |
| Current page structure | `read_page` |
| Tab-scoped screenshots, clicks, scrolling or hover | `computer` |
| Input into a specific page field | `form_input` |

Use the fully qualified names and parameters from the live tool schemas. Do not confuse the Chrome `computer` tool with `computer-use-mcp`'s global desktop `computer` tool. Codex's `cua` API and `nameSession` are not automatically available in Claude.

If the Chrome tools are missing, check the session's supported Chrome connection UI. Official CLI documentation uses `/chrome` to inspect status and `claude --chrome` when starting a CLI session; do not start another agent just to test this, and do not assume every Desktop version exposes the same command. The extension must be installed, connected, and authenticated in the intended Claude account/organization. An API key in a hosted app does not connect the local Chrome extension. Report the exact observed connection problem without changing organization or security settings.

## Own tabs and group

1. Read the current tab context, then open a new task tab. Reuse a user's existing tab only when explicitly selected. Keep the returned tab ID, URL and session identity.
2. Claude in Chrome normally creates a group tied to the session. Verify the group if metadata exposes it. Use its supported rename control for `Claude · <short task>` only when available. Never invent a grouping API or rename somebody else's group through global shortcuts.
3. Use explicit tab IDs on every action that accepts one. Re-read context after a closed/invalid tab or lost connection. Avoid targeting an implicit active tab.
4. Keep the task's work/result tabs open because this user wants a visible place to inspect the work. Remove only disposable tabs you created when safe. Never close or move unrelated user tabs.

Groups organize tabs; they do not create a separate login, security boundary or physical mouse. The Chrome integration can share the user's existing sign-ins. A cursor marker shown by a tool is a browser indicator. Use it when offered; don't claim it is a second OS pointer or inject a decorative overlay and call that working control.

## Background input

- Use page-scoped clicks and field input. Get current page structure before choosing an element. For coordinate actions, use a fresh screenshot from that same tab and controller.
- Keep Chrome and the user's current tab unfocused when the interface supports it. Do not add `activate`, `focus`, global Cmd+L/Alt+Tab, system typing, or clipboard changes to make browser actions work.
- Check the actual outcome after each meaningful action. A green tool response alone does not prove the correct field changed.
- Do not combine global desktop input with browser automation while the user is active. If a required action only works with takeover, pause that action and explain it before asking for a brief handoff.
- Native file pickers, browser permission prompts, downloads dialogs and login challenges may require a handoff. Prefer supported upload/download APIs that stay in the task tab. Respect their approvals; never route around a denial.
- If the user edits the same target tab, yield it. Other tabs/apps remain theirs to use; don't repeatedly pause because of unrelated typing.
- Keep going while the user works elsewhere. Their selected Chrome tab, the front app, the system pointer and the clipboard are theirs: never change them, and never stop or slow your own tab's work because they are using them. Observed 2026-10-18 with Claude in Chrome: tab-scoped click, type, Return, scroll, page JavaScript and tab screenshots all worked on the work tab while another app was in front, with no front-app switch and no clipboard change. Under the extension's debugger, `document.visibilityState` and `document.hasFocus()` in the work tab read `visible`/`true` even while another app is frontmost, so don't use them as evidence of focus.

## Small background check

Run in Claude's actual browser session before calling it verified. Preserve any ongoing test; don't repeat a consequential task to prove the connection.

1. Create a disposable work tab in the session's group. Observe its actual URL/title and rendered page.
2. Perform a harmless read or navigation on a public documentation page. If a public search field is available, enter a non-sensitive test word through the tab-scoped input tool and read back the result. Use normal UI search, not hidden app state.
3. Where the interface exposes the user's selected tab/window without changing it, compare it before and after. Do not actively switch a personal tab to manufacture this evidence. The user may keep working elsewhere during the check.
4. Confirm the intended page changed and no global input was used. If foreground state is not observable, say tab-scoped actions passed but non-interference is not independently verified. Do not claim no focus theft solely because a screenshot succeeded.
5. Stop and correct the control path if it steals focus or affects a different tab. No fallback to the physical pointer. Preserve the result tab for inspection and report what was tested.

Suggested user invocation:

```text
/computer-control background Use Claude in Chrome in your own task tab group. Keep my mouse, keyboard, clipboard and selected tabs untouched. Do one harmless browser check with the available tools, then perform my requested task only in your work tabs. Keep the result tab open. If isolated Chrome control is unavailable, tell me the exact blocker; don't switch to my physical mouse.
```

Sources checked 2026-10-18: [Claude in Chrome](https://code.claude.com/docs/en/chrome), [Desktop browser choices](https://code.claude.com/docs/en/desktop#choose-between-the-browser-and-the-chrome-extension). The installed Anthropic `chrome-browser` and `built-in-browser` skills describe the session-specific tool routing; follow the copies actually available in the current session.
