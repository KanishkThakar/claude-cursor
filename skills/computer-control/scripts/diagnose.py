#!/usr/bin/env python3
"""Read selected Claude configuration metadata; do not start tools or alter state."""
from pathlib import Path
import json
import platform
import plistlib
import shutil


def inspect(home=None, app_roots=None):
    home = Path.home() if home is None else Path(home)
    roots = [Path('/Applications'), home / 'Applications'] if app_roots is None else app_roots
    result = {'platform': platform.system(), 'claude_cli_present': bool(shutil.which('claude')),
              'configuration': [], 'computer_use_servers': [],
              'note': 'Read-only metadata check. App permissions and actual mouse movement are not tested.'}
    for root in roots:
        p = Path(root) / 'Claude.app/Contents/Info.plist'
        if p.is_file():
            try:
                app = plistlib.loads(p.read_bytes())
                result['desktop'] = {'version': app.get('CFBundleShortVersionString'),
                                     'bundle_id': app.get('CFBundleIdentifier')}
            except (OSError, ValueError, plistlib.InvalidFileException):
                result['desktop'] = {'status': 'metadata_unreadable'}
            break
    paths = [home / '.claude.json', home / '.claude/settings.json',
             home / 'Library/Application Support/Claude/claude_desktop_config.json']
    for p in paths:
        if not p.is_file():
            continue
        entry = {'file': str(p), 'status': 'readable'}
        try:
            data = json.loads(p.read_text())
            if not isinstance(data, dict):
                raise ValueError('Expected object')
        except (OSError, ValueError):
            entry['status'] = 'unreadable_or_invalid_json'
            result['configuration'].append(entry)
            continue
        servers = data.get('mcpServers', {})
        if isinstance(servers, dict):
            for name in ['computer-use-mcp', 'computer-use', 'node_repl']:
                server = servers.get(name)
                if not isinstance(server, dict):
                    continue
                command = server.get('command')
                exists = False
                if isinstance(command, str) and command:
                    exists = Path(command).is_file() if Path(command).is_absolute() else bool(shutil.which(command))
                result['computer_use_servers'].append({
                    'name': name, 'config_file': str(p),
                    'transport': server.get('type', 'stdio' if command else 'unspecified'),
                    'executable_present': exists,
                    'health': 'not_tested',
                })
        result['configuration'].append(entry)
    skill = home / '.claude/skills/computer-control/SKILL.md'
    result['personal_skill_present'] = skill.is_file()
    return result


if __name__ == '__main__':
    print(json.dumps(inspect(), indent=2))
