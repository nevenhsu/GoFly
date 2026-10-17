#!/usr/bin/env python3
"""Compile ABI assertions against the generated header without importing it in Swift."""
from pathlib import Path
import re
import subprocess

bridge = Path(__file__).resolve().parent
output = bridge.parents[2] / 'work/gofly-ios/native'
shim = (bridge / 'include/idevice.h').read_text()
prototypes = re.findall(
    r'(?m)^((?:struct IdeviceFfiError \*|void |plist_type |const char\* )([a-z_][a-z_0-9]*)\([^;]*\);)',
    shim,
)
if len(prototypes) != 30:
    raise SystemExit('Unexpected Swift shim API count')
checks = ['#include "idevice-full.h"\n#include <stddef.h>\n']
# Compare the actual shim definitions, renamed to coexist with the generated
# header. Function-pointer compatibility alone cannot detect a changed layout.
for name, fields in {
    'IdeviceFfiError': ['code', 'sub_code', 'message'],
    'InstalledCryptexC': ['identifier', 'version'],
}.items():
    definition = re.search(r'typedef struct ' + name + r'\s*\{[^}]*\}\s*' + name + ';', shim)
    if not definition:
        raise SystemExit('Missing shim ABI definition: ' + name)
    renamed = 'GoFlyShim' + name
    checks.append(re.sub(r'\b' + name + r'\b', renamed, definition.group()) + '\n')
    for expression in ['sizeof', '_Alignof']:
        checks.append(f'_Static_assert({expression}({renamed}) == {expression}({name}), "{name} {expression}");\n')
    for field in fields:
        checks.append(f'_Static_assert(offsetof({renamed}, {field}) == offsetof({name}, {field}), "{name}.{field} offset");\n')
enum_definition = re.search(r'typedef enum\s*\{[^}]*\}\s*plist_type;', shim)
if not enum_definition:
    raise SystemExit('Missing shim plist_type definition')
enumerators = re.findall(r'\bPLIST_[A-Z_]+\b', enum_definition.group())
renamed_enum = enum_definition.group().replace('plist_type', 'GoFlyShimPlistType')
for enumerator in enumerators:
    renamed_enum = re.sub(r'\b' + enumerator + r'\b', 'GoFlyShim_' + enumerator, renamed_enum)
checks.append(renamed_enum + '\n')
checks.append('_Static_assert(sizeof(GoFlyShimPlistType) == sizeof(plist_type), "plist_type size");\n')
checks.append('_Static_assert(_Alignof(GoFlyShimPlistType) == _Alignof(plist_type), "plist_type alignment");\n')
for enumerator in enumerators:
    checks.append(f'_Static_assert((int)GoFlyShim_{enumerator} == (int){enumerator}, "{enumerator} value");\n')
for declaration, name in prototypes:
    checks.append(declaration.replace(name + '(', 'gofly_shim_' + name + '(', 1) + '\n')
    checks.append('_Static_assert(__builtin_types_compatible_p(__typeof__(&' + name + '), __typeof__(&gofly_shim_' + name + ')), "ABI mismatch: ' + name + '");\n')
path = output / 'shim-abi-check.c'
path.write_text(''.join(checks))
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-fsyntax-only', '-target', 'arm64-apple-ios26.0', '-isysroot', sdk, str(path)], check=True)
symbols = subprocess.check_output(['nm', '-gjU', str(output / 'libidevice_ffi.a')], text=True, stderr=subprocess.DEVNULL).splitlines()
missing = [name for _, name in prototypes if '_' + name not in symbols]
if missing:
    raise SystemExit('Archive missing Swift shim symbols: ' + ', '.join(missing))
print('All 30 Swift shim declarations, struct layouts and plist enum values match generated ABI/archive')
