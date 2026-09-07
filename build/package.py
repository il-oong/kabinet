"""Create a versioned RBZ using only Python's standard library."""
from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parent.parent
version = re.search(r"VERSION\s*=\s*'([^']+)'", (root / 'kabinet/version.rb').read_text(encoding='utf-8')).group(1)
output = root / 'build' / f'kabinet-{version}.rbz'
temporary = output.with_suffix('.tmp')
files = [root / 'kabinet_loader.rb'] + sorted(p for p in (root / 'kabinet').rglob('*') if p.is_file())
try:
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            archive.write(file, file.relative_to(root).as_posix())
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('RBZ integrity check failed')
        assert len(archive.namelist()) == len(files)
    temporary.replace(output)
finally:
    if temporary.exists():
        temporary.unlink()
print(f'{output} ({len(files)} files, {output.stat().st_size:,} bytes)')
