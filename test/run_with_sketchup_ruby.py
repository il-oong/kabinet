"""Run pure Ruby checks using the installed SketchUp Ruby DLL (no SketchUp UI).

Usage: python test/run_with_sketchup_ruby.py test/live_preview_test.rb
This does NOT load the native SketchUp API. Geometry tests use explicit doubles.
"""
import ctypes
import json
import os
from pathlib import Path
import sys

root = Path(os.environ.get('KABINET_SKETCHUP_DIR', r'C:\Program Files\SketchUp\SketchUp 2022'))
dll = next(root.glob('*ruby*.dll'))
handles = [os.add_dll_directory(str(root)), os.add_dll_directory(str(root / 'Tools/RubyStdLib/platform_specific'))]
ruby = ctypes.CDLL(str(dll))
argc = ctypes.c_int(1)
args = (ctypes.c_char_p * 2)(b'ruby', None)
argv = ctypes.cast(args, ctypes.POINTER(ctypes.c_char_p))
ruby.ruby_sysinit(ctypes.byref(argc), ctypes.byref(argv))
stack = ctypes.c_size_t()
ruby.ruby_init_stack(ctypes.byref(stack))
if ruby.ruby_setup() != 0:
    raise RuntimeError('Ruby setup failed')
ruby.rb_eval_string_protect.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
ruby.rb_eval_string_protect.restype = ctypes.c_size_t
stdlib = (root / 'Tools/RubyStdLib').as_posix()
script = Path(sys.argv[1]).resolve().as_posix()
code = (
    f'$LOAD_PATH.unshift({json.dumps(stdlib)}, {json.dumps(stdlib + "/platform_specific")}); '
    f'begin; load {json.dumps(script, ensure_ascii=False)}; '
    'rescue Exception => e; warn e.full_message; raise; ensure; STDOUT.flush; STDERR.flush; end'
)
state = ctypes.c_int()
ruby.rb_eval_string_protect(code.encode('utf-8'), ctypes.byref(state))
ruby.ruby_cleanup(0 if state.value == 0 else 1)
sys.exit(0 if state.value == 0 else 1)
