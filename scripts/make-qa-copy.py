"""Create a separate, disposable app/database for visual QA; never uses personal data."""
from pathlib import Path
import plistlib, shutil
root = Path('/tmp/Opus-Redesign-QA-Data')
root.mkdir(exist_ok=True)
target = Path('/tmp/Opus-Redesign-QA.app')
shutil.copytree(Path('dist/Opus.app'), target, dirs_exist_ok=True)
info = target / 'Contents/Info.plist'
settings = plistlib.loads(info.read_bytes())
settings.update(CFBundleIdentifier='com.ruben.opus.qa.redesign', CFBundleName='Opus Design QA', CFBundleDisplayName='Opus Design QA', LSEnvironment={'OPUS_DATA_DIR': str(root)})
info.write_bytes(plistlib.dumps(settings))
# Leave the database empty. The application creates its schema on first launch.
print(target)
