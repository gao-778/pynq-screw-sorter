# 上传 GitHub 的步骤

此目录是准备发布的源码树。`external/`、`build/` 和原完整 ZIP 属于本地材料，不能整盘拖进 GitHub。

## 本次可以让 Codex 代做

提供你的 **GitHub 仓库网页地址**，例如 `https://github.com/你的用户名/pynq-screw-sorter`。尚未建仓库时，提供账号和想用的仓库名即可。授权登录需要在浏览器或 Git 凭据管理器中完成；不要把密码或访问令牌发在对话里。

可代做的流程是：检查上传清单 → 配置远程仓库 → 提交源码 → 推送 → 回读远端提交核对。已有仓库会先读取分支历史，不强制覆盖。

## 自己上传

1. 在 GitHub 创建空仓库。首次导入时不勾选生成 README、LICENSE 或 `.gitignore`，本目录已经包含这些文件。
2. 打开本目录的终端，先检查待上传范围：

```powershell
git status --short
python scripts/check_repository.py
git check-ignore external/IMPORT.json
```

3. 如果仓库还未初始化，执行 `git init -b main`。设置提交署名时，可以使用自己 GitHub 设置中提供的隐私 noreply 邮箱；不要直接复制别人的邮箱。
4. 确认文件清单后提交、关联自己的空仓库并推送：

```powershell
git add .
git diff --cached --stat
git commit -m "Publish PYNQ-Z2 screw sorter source snapshot"
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

如果已经有 `origin`，先用 `git remote -v` 确认地址；如果远端已有提交，先检查并合并历史，不使用 `--force`。

5. 打开 GitHub 仓库，核对 README、MIT 及第三方说明、软件/RTL/模型是否齐全，并确认没有 `external/`、`RUNLOG.TXT`、缓存和原始数据。

## BOOT 和 Release 附件

通常可把经审核的二进制放在 GitHub Releases，源码留在 Git。GitHub 普通 Git 文件的硬上限为 100 MiB；本次筛选后的单个文件低于该限制，不需要仅因本次源码而启用 LFS。

但当前原始 BOOT/bit 含未完成公开许可核对的资源，**本次不上传原 BOOT 或原完整交付 ZIP**。之后补齐许可或使用可公开资源重建并验证，再单独发布附件；不要把忽略规则解除后直接上传。

参考：[GitHub 导入本地代码](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)、[大文件与 Release](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)、[仓库许可证](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。
