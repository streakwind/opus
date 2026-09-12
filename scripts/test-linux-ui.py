#!/usr/bin/env python3
"""Run under Xvfb/DBus on Linux. No production database or seeded defaults."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

artifacts = Path('/tmp/opus-linux-ui')
artifacts.mkdir(exist_ok=True)

def command(*args):
    return subprocess.check_output(args, text=True).strip()

def wait_for(check, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                return value
        except (subprocess.CalledProcessError, sqlite3.Error):
            pass
        time.sleep(.1)
    raise AssertionError('Timed out waiting for GTK / persisted task')

def window(name):
    return command('xdotool', 'search', '--onlyvisible', '--name', '^' + name + '$').splitlines()[0]

with tempfile.TemporaryDirectory(prefix='opus-ui-') as data:
    env = dict(os.environ, OPUS_DATA_DIR=data, GDK_BACKEND='x11')
    process = subprocess.Popen(['.build/release/opus'], env=env)
    try:
        main = wait_for(lambda: window('Opus'))
        command('xdotool', 'windowfocus', '--sync', main)
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+n')
        dialog = wait_for(lambda: window('New task'))
        command('xdotool', 'windowfocus', '--sync', dialog)
        command('xdotool', 'type', '--clearmodifiers', 'Interface test task')
        command('import', '-window', 'root', str(artifacts / 'editor.png'))
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+Return')
        def saved():
            with sqlite3.connect(Path(data) / 'Opus.sqlite') as db:
                return [json.loads(row[0]) for row in db.execute('SELECT payload FROM tasks')]
        tasks = wait_for(saved)
        assert len(tasks) == 1 and tasks[0]['title'] == 'Interface test task'
        assert not tasks[0]['completed']
        time.sleep(.3)
        command('import', '-window', 'root', str(artifacts / 'tasks.png'))
        command('xdotool', 'windowfocus', '--sync', main)
        command('xdotool', 'key', '--clearmodifiers', 'ctrl+q')
        assert process.wait(timeout=10) == 0
        subprocess.run(['.build/release/opus', '--smoke-test'], env=env, check=True, timeout=15)
        assert saved()[0]['id'] == tasks[0]['id']
        print('GTK keyboard creation and database reopening passed.')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
