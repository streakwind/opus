#!/usr/bin/env python3
"""Accessibility-targeted Linux UI checks under Xvfb/DBus. No seeded data."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

artifacts = Path('/tmp/opus-linux-ui')
artifacts.mkdir(exist_ok=True)

try:
    import gi
    gi.require_version('Atspi', '2.0')
    from gi.repository import Atspi
except Exception as error:  # pragma: no cover
    raise SystemExit(f'python3-gi / Atspi required for Linux UI checks: {error}') from error


def command(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def wait_for(check, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                return value
        except Exception:
            pass
        time.sleep(0.1)
    raise AssertionError('Timed out waiting for UI / persistence')


def window_id(name: str) -> str:
    return command('xdotool', 'search', '--onlyvisible', '--name', f'^{name}$').splitlines()[0]


def desktop():
    Atspi.init()
    return Atspi.get_desktop(0)


def find_accessible(name: str, role=None, root=None):
    def match(node):
        try:
            if node.get_name() != name:
                return False
            if role is not None and node.get_role_name() != role:
                return False
            return True
        except Exception:
            return False

    def walk(node, depth=0):
        if depth > 35 or node is None:
            return None
        if match(node):
            return node
        try:
            count = node.get_child_count()
        except Exception:
            return None
        for index in range(count):
            found = walk(node.get_child_at_index(index), depth + 1)
            if found:
                return found
        return None

    return wait_for(lambda: walk(root or desktop()))


def click(name: str, role=None):
    node = find_accessible(name, role=role)
    action = node.get_action_iface()
    assert action is not None, f'No action interface for {name}'
    assert action.do_action(0), f'Failed to activate {name}'
    return node


def focus_and_type(window_name: str, text: str):
    wid = wait_for(lambda: window_id(window_name))
    command('xdotool', 'windowraise', wid)
    command('xdotool', 'windowfocus', '--sync', wid)
    time.sleep(0.2)
    command('xdotool', 'type', '--clearmodifiers', '--delay', '12', text)


def dismiss_help_if_present():
    try:
        wait_for(lambda: window_id('Quick start'), timeout=3)
    except AssertionError:
        return
    for _ in range(5):
        try:
            click('Next', role='push button')
            time.sleep(0.15)
        except AssertionError:
            break
    try:
        click('Done', role='push button')
    except AssertionError:
        try:
            click('Close', role='push button')
        except AssertionError:
            pass


with tempfile.TemporaryDirectory(prefix='opus-ui-') as data:
    env = dict(os.environ, OPUS_DATA_DIR=data, GDK_BACKEND='x11', GTK_A11Y='atspi')
    process = subprocess.Popen(['dist/linux/bin/opus'], env=env)
    try:
        main = wait_for(lambda: window_id('Opus'))
        command('xdotool', 'windowfocus', '--sync', main)
        dismiss_help_if_present()

        click('nav-inbox')
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+n')
        wait_for(lambda: window_id('New work'))
        focus_and_type('New work', 'Interface test task')
        command('import', '-window', window_id('New work'), str(artifacts / 'editor.png'))
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+Return')

        db = Path(data) / 'Opus.sqlite'

        def tasks():
            with sqlite3.connect(db) as conn:
                return [json.loads(row[0]) for row in conn.execute('SELECT payload FROM tasks')]

        saved = wait_for(lambda: tasks() if tasks() else None)
        assert len(saved) == 1 and saved[0]['title'] == 'Interface test task'
        task_id = saved[0]['id']

        click(f'toggle-{task_id}')
        wait_for(lambda: tasks()[0]['completed'])
        command('xdotool', 'windowfocus', '--sync', main)
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+shift+z')
        wait_for(lambda: not tasks()[0]['completed'])

        click('nav-calendar')
        find_accessible('calendar-period-week')
        click('nav-schedule')
        find_accessible('schedule-period-week')
        click('nav-rhythm')
        find_accessible('add-rhythm')

        click('Settings')
        find_accessible('set-appearance')
        click('settings-done')

        click(f'delete-work-{task_id}')
        wait_for(lambda: tasks() == [])
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+shift+z')
        wait_for(lambda: len(tasks()) == 1)

        command('import', '-window', 'root', str(artifacts / 'shell.png'))
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+q')
        assert process.wait(timeout=10) == 0
        subprocess.run(['dist/linux/bin/opus', '--smoke-test'], env=env, check=True, timeout=15)
        assert tasks()[0]['id'] == task_id
        print('Accessibility UI checks passed for tasks, calendar, schedule, rhythm, and persistence.')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
