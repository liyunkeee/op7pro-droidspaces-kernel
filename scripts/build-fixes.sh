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

# Fix 7: event_timer timerqueue_head init (CVE-2021-20317 changed struct)
if grep -q '\.head = RB_ROOT' drivers/soc/qcom/event_timer.c 2>/dev/null; then
  sed -i 's/\.head = RB_ROOT,/.rb_root = RB_ROOT_CACHED,/' drivers/soc/qcom/event_timer.c
  sed -i '/\.next = NULL,/d' drivers/soc/qcom/event_timer.c
  echo "[+] Fix 7: event_timer init"
fi

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

echo "[*] All toolchain build fixes applied."
