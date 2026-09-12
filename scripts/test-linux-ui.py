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

# Dogtail checks this desktop setting during import, even in headless CI.
subprocess.run(
    ['gsettings', 'set', 'org.gnome.desktop.interface', 'toolkit-accessibility', 'true'],
    check=False,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)

try:
    from dogtail.tree import root as accessibility_root
except Exception as error:  # pragma: no cover
    raise SystemExit(f'python3-dogtail required for Linux UI checks: {error}') from error


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


def find_accessible(name: str, role=None, root=None):
    names = {name} if isinstance(name, str) else set(name)

    def match(node):
        try:
            if node.name not in names:
                return False
            if role is not None and node.roleName != role:
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
            children = node.children
        except Exception:
            return None
        for child in children:
            found = walk(child, depth + 1)
            if found:
                return found
        return None

    try:
        return wait_for(lambda: walk(root or accessibility_root))
    except AssertionError:
        try:
            accessibility_root.dump()
        except Exception:
            pass
        raise


def activate(node, description: str):
    original = node
    while node is not None:
        for action in ('click', 'toggle', 'press'):
            if action in node.actions:
                assert node.doActionNamed(action), f'Failed to invoke {action} on {description}'
                return node
        node = node.parent
    if original.focusable:
        assert original.grabFocus(), f'Failed to focus {description}'
        command(
            'xdotool', 'key', '--clearmodifiers',
            'space' if original.roleName in ('check box', 'toggle button') else 'Return',
        )
        return original
    original.click()
    return original


def click(name: str, role=None):
    return activate(find_accessible(name, role=role), str(name))


def descendants(node):
    for child in node.children:
        yield child
        yield from descendants(child)


def work_row(title: str):
    node = find_accessible(title)
    while node is not None:
        controls = list(descendants(node))
        buttons = [item for item in controls if item.roleName == 'push button']
        if len(buttons) >= 3:
            return node, buttons[0], buttons
        node = node.parent
    raise AssertionError(f'Could not locate controls for {title}')


def focus_and_type(text: str):
    wid = wait_for(lambda: window_id('Opus'))
    command('xdotool', 'windowraise', wid)
    command('xdotool', 'windowfocus', '--sync', wid)
    time.sleep(0.2)
    command('xdotool', 'type', '--clearmodifiers', '--delay', '12', text)


def dismiss_help_if_present():
    try:
        wait_for(lambda: window_id('Quick start'), timeout=3)
    except AssertionError:
        return
    for _ in range(4):
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


def courses(db: Path):
    with sqlite3.connect(db) as conn:
        return [json.loads(row[0]) for row in conn.execute('SELECT payload FROM courses')]


with tempfile.TemporaryDirectory(prefix='opus-ui-') as data:
    env = dict(os.environ, OPUS_DATA_DIR=data, GDK_BACKEND='x11', GTK_A11Y='atspi')
    process = subprocess.Popen(['dist/linux/bin/opus'], env=env)
    try:
        main = wait_for(lambda: window_id('Opus'))
        command('xdotool', 'windowfocus', '--sync', main)
        dismiss_help_if_present()

        click(('nav-inbox', 'Inbox'))
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+n')
        find_accessible(('editor-cancel', 'Cancel'))
        # Focus the title field inside the in-window editor overlay.
        title = find_accessible('Title', role='label')
        try:
            parent = title.parent
            for child in parent.children:
                if child.roleName == 'text' and child.focusable:
                    child.grabFocus()
                    break
        except Exception:
            pass
        focus_and_type('Interface test task')
        command('import', '-window', main, str(artifacts / 'editor.png'))
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+Return')

        db = Path(data) / 'Opus.sqlite'

        def tasks():
            with sqlite3.connect(db) as conn:
                return [json.loads(row[0]) for row in conn.execute('SELECT payload FROM tasks')]

        saved = wait_for(lambda: tasks() if tasks() else None)
        assert len(saved) == 1 and saved[0]['title'] == 'Interface test task'
        task_id = saved[0]['id']

        _, toggle, _ = work_row('Interface test task')
        activate(toggle, 'task completion')
        wait_for(lambda: tasks()[0]['completed'])
        command('xdotool', 'windowfocus', '--sync', main)
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+shift+z')
        wait_for(lambda: not tasks()[0]['completed'])

        click(('nav-calendar', 'Calendar'))
        find_accessible(('calendar-period-week', 'Week'))
        find_accessible('No due date')
        click(('nav-schedule', 'Schedule'))
        find_accessible(('schedule-period-week', 'Week'))
        click(('nav-rhythm', 'Rhythm'))
        find_accessible(('add-rhythm', 'Add a rhythm…'))

        # Save a list with class times (regression for the save crash).
        click(('New list button', 'New list'))
        find_accessible(('New list', 'Edit list', 'editor-cancel', 'Cancel', 'NAME'))
        name_label = find_accessible(('NAME', 'Name'), role='label')
        try:
            parent = name_label.parent
            for child in parent.children:
                if child.roleName == 'text' and child.focusable:
                    child.grabFocus()
                    break
        except Exception:
            pass
        focus_and_type('Physics Lab')
        try:
            click('Add class time', role='push button')
        except AssertionError:
            pass
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+Return')
        wait_for(lambda: any(course.get('name') == 'Physics Lab' for course in courses(db)))
        saved_course = next(course for course in courses(db) if course.get('name') == 'Physics Lab')
        assert saved_course.get('name') == 'Physics Lab'

        click('Settings')
        find_accessible(('set-appearance', 'Appearance', 'APPEARANCE'))
        click(('settings-done', 'Done'))

        click(('nav-inbox', 'Inbox'))
        _, _, row_buttons = work_row('Interface test task')
        activate(row_buttons[-1], 'delete task')
        wait_for(lambda: tasks() == [])
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+shift+z')
        wait_for(lambda: len(tasks()) == 1)

        command('import', '-window', 'root', str(artifacts / 'shell-light.png'))
        # Toggle dark appearance for a second screenshot when settings allow it.
        click('Settings')
        find_accessible(('set-appearance', 'Appearance', 'APPEARANCE'))
        try:
            click('Dark')
        except AssertionError:
            pass
        click(('settings-done', 'Done'))
        time.sleep(0.3)
        command('import', '-window', 'root', str(artifacts / 'shell-dark.png'))

        command('xdotool', 'key', '--clearmodifiers', 'ctrl+q')
        assert process.wait(timeout=10) == 0
        subprocess.run(['dist/linux/bin/opus', '--smoke-test'], env=env, check=True, timeout=15)
        assert tasks()[0]['id'] == task_id
        css = Path('dist/linux/share/opus/opus.css')
        assert css.is_file(), 'Bundled Opus CSS missing from Linux package'
        print('Accessibility UI checks passed for tasks, calendar, schedule, rhythm, class times, and persistence.')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
