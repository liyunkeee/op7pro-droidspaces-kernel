#!/bin/bash
# build-fixes.sh - toolchain fixes for 2019-era Qualcomm code with Clang 14
# Based on kirisakura-ksu-op7pro build.sh (verified working on this SoC).
# Called from GitHub Actions workflow inside the kernel source tree.
set -e

echo "[*] Applying toolchain build fixes..."

# Fix 1: gcc-wrapper.py Python 2 -> Python 3 (kernel's scripts/gcc-wrapper.py
#        is Python 2; Ubuntu 22.04 has Python 3 only)
cp "$GITHUB_WORKSPACE/scripts/gcc-wrapper.py" scripts/gcc-wrapper.py
chmod +x scripts/gcc-wrapper.py
echo "[+] Fix 1: gcc-wrapper.py Python2->Python3"

# Fix 2: Relax -Werror globally (2019 Qualcomm code produces warnings that
#        become errors under GCC 11 / Clang 14)
python3 - <<'PYEOF'
from pathlib import Path
import re
root = Path(".")
paths = list(root.rglob("Makefile")) + list(root.rglob("Kbuild"))
for path in paths:
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except Exception:
        continue
    new = text
    new = new.replace("-Werror-implicit-function-declaration",
                      "-Wno-error=implicit-function-declaration")
    new = re.sub(r"(?<![A-Za-z0-9_-])-Werror=([A-Za-z0-9_-]+)",
                 r"-Wno-error=\1", new)
    new = re.sub(r"(?<![A-Za-z0-9_-])-Werror(?![=A-Za-z0-9_-])",
                 "-Wno-error", new)
    if new != text:
        path.write_text(new)
PYEOF
echo "[+] Fix 2: -Werror relaxed globally"

# Fix 3: selinux_state __rticdata relocation overflow
sed -i 's/struct selinux_state selinux_state __rticdata;/struct selinux_state selinux_state;/' \
  security/selinux/hooks.c
echo "[+] Fix 3: selinux_state __rticdata removed"

# Fix 8: KALLSYMS_BASE_RELATIVE overflow (large kernel image with security patches)
sed -i 's/default !IA64 && !(TILE && 64BIT)/default n/' init/Kconfig
echo "[+] Fix 8: KALLSYMS_BASE_RELATIVE disabled"

# Fix 4: ipa_hw_stats.c copy_from_user missing size guard
# (Clang's FORTIFY catches copy destination size too small in
#  ipa_debugfs_enable_disable_drop_stats)
if grep -q 'copy_from_user(dbg_buff, ubuf, count)' drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c 2>/dev/null; then
  sed -i 's/copy_from_user(dbg_buff, ubuf, count)/copy_from_user(dbg_buff, ubuf, min_t(size_t, count, sizeof(dbg_buff)))/g' \
    drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c
  echo "[+] Fix 4: ipa_hw_stats copy_from_user size guard"
fi

# Fix 9: include/soc/oplus/lowmem_dbg.h - restore original LOS content.
#        dma-buf.c has the real `inline int oplus_is_dma_buf_file(struct file *)`
#        implementation (guarded by OPLUS_FEATURE_LOWMEM_DBG). The header only
#        declares it; a wrong stub here (bool + body) causes conflicting types.
if [ -f include/soc/oplus/lowmem_dbg.h ]; then
  if grep -q 'oplus_is_dma_buf_file' include/soc/oplus/lowmem_dbg.h && \
     grep -q 'return false' include/soc/oplus/lowmem_dbg.h; then
    cat > include/soc/oplus/lowmem_dbg.h << 'HEOF'
/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef __LOWMEM_DBG_H
#define __LOWMEM_DBG_H

void oplus_lowmem_dbg(bool critical);

#ifndef CONFIG_MTK_ION
inline int oplus_is_dma_buf_file(struct file *file);
#endif /* CONFIG_MTK_ION */

#endif /* __LOWMEM_DBG_H */
HEOF
    echo "[+] Fix 9: lowmem_dbg.h restored to original LOS content"
  fi
fi

# Fix: disable MODULE_SIG_FORCE (blocks unsigned modules)
sed -i 's/CONFIG_MODULE_SIG_FORCE=y/# CONFIG_MODULE_SIG_FORCE is not set/' \
  arch/arm64/configs/vendor/sm8150-perf_defconfig
echo "[+] Fix: MODULE_SIG_FORCE disabled"

# Fix 10: Clang 拒绝尖括号相对路径 include (GCC 接受)
#        例: #include <../sched/sched.h> -> #include "../sched/sched.h"
#        注意: 只替换整个路径以 ./ 或 ../ 开头且以 .h/.c/.S 等结尾的完整 include
python3 - <<'PYEOF'
import re
from pathlib import Path
count = 0
for path in Path(".").rglob("*"):
    if path.suffix not in (".c", ".h", ".S"):
        continue
    if "out" in path.parts:
        continue
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        continue
    # 只匹配 <../xxx.h> 或 <./xxx.h> (路径只含字母数字/点/下划线/连字符/斜杠)
    new = re.sub(r'#(\s*)include\s+<(\.{1,2}/[A-Za-z0-9_./-]+)>', r'#\1include "\2"', text)
    if new != text:
        path.write_text(new)
        count += 1
print(f"[+] Fix 10: fixed {count} files with relative-path angle-bracket includes")
PYEOF


# Fix 11: hardcoded 'kernel/msm-4.14/' include paths in oplus charger_ic
# (OnePlus source assumes tree layout 'kernel/msm-4.14' parallel to vendor/,
#  but our kernel source root IS the msm-4.14 tree. Rewrite relative includes
#  to point at the in-tree drivers/power/supply/qcom/ copies.)
python3 - << 'PYEOF'
import re
from pathlib import Path
base = Path("drivers/power/oplus/charger_ic")
count = 0
if base.exists():
    for path in base.iterdir():
        if path.suffix not in (".c", ".h"):
            continue
        text = path.read_text(errors="ignore")
        new = re.sub(
            r'#(\s*)include\s+"(?:\.{2}/)+kernel/msm-4\.14/drivers/power/supply/qcom/(.*)"',
            r'#\1include "../../supply/qcom/\2"',
            text)
        if new != text:
            path.write_text(new)
            count += 1
print(f"[+] Fix 11: rewrote {count} files with hardcoded kernel/msm-4.14 paths")
PYEOF


# Fix 12: oplus_healthinfo.c references 'ionwait_para' which is only defined
# in non-open-sourced OPLUS ION code. Insert a static zeroed struct so the
# ion_wait proc node just prints zeros (harmless debug interface).
python3 - << 'FIX12EOF'
from pathlib import Path
p = Path("drivers/soc/oplus/oplus_healthinfo/oplus_healthinfo.c")
if p.exists():
    text = p.read_text(errors="ignore")
    if "ionwait_para" in text and "static struct ion_wait_para ionwait_para" not in text:
        marker = "static ssize_t ion_wait_read("
        if marker in text:
            text = text.replace(
                marker,
                "static struct ion_wait_para ionwait_para;\n\n" + marker,
                1)
            p.write_text(text)
            print("[+] Fix 12: added static ionwait_para definition")
        else:
            print("[!] Fix 12: marker not found, skipping")
    else:
        print("[+] Fix 12: not needed")
else:
    print("[!] Fix 12: oplus_healthinfo.c not found")
FIX12EOF
echo "[*] All toolchain build fixes applied."