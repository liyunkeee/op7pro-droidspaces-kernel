# OnePlus 7 Pro (GM1910) — Droidspaces + KernelSU-Next 内核自编译

**目标**：在 GitHub Actions 上云编译 4.14.180 内核（与你手机出厂版本完全一致），集成：
- ✅ **KernelSU-Next v3.x**（legacy 分支，替代已淘汰的 v0.9.5 旧 KSU）
- ✅ **Droidspaces 全部必需配置**（PID/IPC/UTS/USER 命名空间、CGROUP_DEVICE、DEVTMPFS、SYSVIPC、POSIX_MQUEUE 等）
- ✅ **Droidspaces 官方 non-GKI 补丁**（xt_qtaguid panic 修复 + cgroup 前缀恢复）
- ✅ **基础配置 = 你手机当前内核的 config**（保留酷安内核全部调优）

## 使用方法（一键云编译）

1. 将整个目录 push 到你的 GitHub 仓库（无需 fork，直接新建仓库上传即可）
2. 点击仓库顶部 **Actions** → 左侧 **Build OP7Pro 4.14.180 Kernel** → **Run workflow** → **Run**
3. 等待约 30~60 分钟（免费额度）
4. 编译完成后，进入该次 run，底部 **Artifacts** 下载 `op7pro-droidspaces-kernel`
5. 解压得到 `AnyKernel3-op7pro-droidspaces-ksu.zip`

## 刷入

**前提**：bootloader 已解锁（你的已解锁，当前就是 KSU 内核）

```
adb reboot recovery      # 进入 TWRP
# TWRP: Install → 选择 AnyKernel3-op7pro-droidspaces-ksu.zip → 刷入
adb reboot
```

或用 KernelFlasher（免 TWRP）刷。

刷完装 **KernelSU-Next 管理器**（GitHub 搜 `rifsxd/KernelSU-Next` Releases 下载 manager APK）。

## 验证

```bash
# 1. root
su
# 2. Droidspaces 需求检查
droidspaces check
```

预期：全部绿勾。

## 文件说明

| 文件 | 作用 |
|---|---|
| `.github/workflows/build.yml` | GitHub Actions 云编译工作流（核心） |
| `kernel-config-base` | 从你手机提取的当前内核 .config（6270 行） |
| `patches/manual-hooks.patch` | KernelSU 手动钩子（execve/faccessat/vfs_read/stat/reboot/setresuid/input） |
| `patches/01.fix_kernel_panic_in_xt_qtaguid.patch` | Droidspaces 官方补丁：修容器网络 panic |
| `patches/02.fix_restore_cgroup.patch` | Droidspaces 官方补丁：cgroup 兼容 systemd |
| `patches/droidspaces.config` | Droidspaces 配置片段 |
| `scripts/build-fixes.sh` | Clang14 编 2019 高通源码的兼容修复 |
| `scripts/gcc-wrapper.py` | gcc-wrapper.py 的 Python3 重写版 |

## 回滚

出问题随时可回退：刷回之前的内核 zip，或用 fastboot 刷备份的 boot.img。

## 已知风险

- Clang 14 编 OnePlusOSS 官方源码 **首次大概率会遇到编译错误**（源码 2019 年的，用 GCC 写的），`build-fixes.sh` 处理了已知坑，但可能有遗漏——看 `build-log` artifact 迭代修复，通常 2~3 轮收敛。
- 新开命名空间（PID/IPC）后某些安全检测（银行类 app）可能更敏感——KSU-Next 自带 SusFS 可缓解。
- 手机: OnePlus 7 Pro GM1910, Android 12 (H2OS C12), 内核 4.14.180, 内核已含 KSU(旧版)。
