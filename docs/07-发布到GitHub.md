# 发布到 GitHub

> 目标：把这个本地仓库推送到你自己的公开 GitHub 仓库，并让 14 次提交正确归属到你名下。
> 前提：本机已装 Git（`git --version` 有输出）。不需要装 `gh`，不需要手动配置 token —— 推送时会自动弹出浏览器登录。

---

## 第 1 步：在 GitHub 上建一个**空**仓库

打开 <https://github.com/new>，填：

| 字段 | 填什么 | 为什么 |
| --- | --- | --- |
| Repository name | `MoveMentor` | 和本地目录名一致，最省事 |
| Description | 把 `README.md` 里那句英文描述粘进去（256 字符那版） | 仓库页首屏就能看到，评审友好 |
| Visibility | **Public** | 参赛要求「仓库公开」是硬指标 |
| Initialize this repository with | **全部不勾**（README / .gitignore / License 都不勾） | ⚠️ **关键**：勾了任何一个，远程就会先有一个提交，本地 14 个提交的历史和它对不上，push 会被拒绝 |

点 **Create repository**。

创建完会跳到仓库首页，显示一屏「quick setup」。**不要用页面上给的那几个命令**（它会让你 `git init` 或 `git remote add` 后 push 一个空仓库，容易走偏）。用下面的步骤。

---

## 第 2 步：配置提交身份（重要，别跳过）

现在本地仓库的作者是占位的 `MoveMentor <movementor@users.noreply.github.com>`。
不改的话，这 14 次提交在 GitHub 上**不会算到你名下**，也不会计入你的贡献图。

把 `<你的用户名>` 和 `<你的邮箱>` 换成你自己的（邮箱建议用 GitHub 提供的匿名地址，不暴露真实邮箱）：

```bash
cd "C:/Users/Z/Desktop/MoveMentor"

git config user.name  "<你的用户名>"
git config user.email "<你的用户名>@users.noreply.github.com"

# 把已有的 14 次提交的作者一起改掉
git commit --amend --reset-author --no-edit
git rebase --exec "git commit --amend --reset-author --no-edit" --root
```

> `git rebase --root` 会把从第一个提交开始的所有提交重写一遍，逐个换成新身份。
> 如果中途停下来，先执行 `git status` 看提示；想放弃就执行 `git rebase --abort` 回到原样。
>
> 只有一次提交时（`git log --oneline | wc -l` 输出 1），`git rebase --root` 可以省略。

改完确认一下：

```bash
git log --format="%an <%ae>  %s" | head -3
```

---

## 第 3 步：添加远程仓库并推送

把 `<你的用户名>` 换掉后执行：

```bash
git remote add origin https://github.com/<你的用户名>/MoveMentor.git
git push -u origin main
```

`git push` 时 Windows 会**自动弹出浏览器窗口**让你登录 GitHub（Git Credential Manager 负责）。
授权一次之后凭据会存进 Windows 凭据管理器，后续推送不用再登录。

> 如果弹窗被拦截或没有出现，改用 SSH：
> ```bash
> git remote set-url origin git@github.com:<你的用户名>/MoveMentor.git
> git push -u origin main
> ```
> SSH 需要你本机已配置密钥（`ssh -T git@github.com` 能返回 `Hi <用户名>!`）。

---

## 第 4 步：验证推送成功

```bash
git remote -v                              # 应显示 origin 指向你的仓库
git log --oneline                          # 14 条提交
git status                                 # 应显示 working tree clean
git ls-remote --heads origin               # 应显示远程的 main 分支与 commit hash
```

打开 `https://github.com/<你的用户名>/MoveMentor`，应该能看到：

- 首屏按 `README.md` 渲染（含六张三段式的演示说明）
- **14 commits** 的提交历史
- `docs/` 下六份参赛文档 + `docs/demo/` 六张演示截图
- `LICENSE` 被识别为 **Apache License 2.0**

---

## 一键脚本（可选）

上面的第 2、3 步已经打包成脚本，省得逐条敲：

```bash
cd "C:/Users/Z/Desktop/MoveMentor"
bash scripts/publish.sh https://github.com/<你的用户名>/MoveMentor.git
```

脚本会：校正身份 → 改写历史作者 → 添加/更新 origin → 推送 → 打印验证结果。
它**不会**做任何破坏性操作（不改写已经推送到远程的历史、不用 `--force`）。

---

## 常见问题

### 推送被拒绝：`! [rejected] main -> main (fetch first)`

说明远程仓库**不是空的**（建仓时勾了 README / License / .gitignore）。

两种处理，任选：

**方案 A（推荐，最干净）**：删掉远程仓库重建一个空仓库，再重新 push。

**方案 B（保留远程那个提交，把本地历史接上去）**：

```bash
git pull --rebase origin main      # 把远程那个提交放到本地历史之前
git push -u origin main
```

如果仓库里的 `README.md` 冲突，`git pull --rebase` 会停下并提示，按提示 `git checkout --theirs README.md`（保留本地版本）后 `git add README.md && git rebase --continue`。

**方案 C（确定远程内容不要了）**：

```bash
git push --force-with-lease -u origin main
```

⚠️ `--force-with-lease` 会**覆盖**远程的 `main` 分支，只在「远程那个提交确实不需要、且没有别人在协作」时才用。它比 `--force` 安全一点，但仍属于破坏性操作。

### 推送成功，但 GitHub 上提交作者不是我

第 2 步没做或做漏了。执行：

```bash
git config user.name  "<你的用户名>"
git config user.email "<你的用户名>@users.noreply.github.com"
git rebase --exec "git commit --amend --reset-author --no-edit" --root
git push --force-with-lease origin main
```

### 认证一直失败 / 反复弹登录窗

凭据被缓存成旧的了，清掉重来：

```bash
git credential-manager erase <<< "protocol=https
host=github.com
"
```

或者打开「Windows 凭据管理器」→「Windows 凭据」→ 找到 `git:https://github.com` 删除，然后重新 push。

如果用的是 Personal Access Token 而不是浏览器登录，注意 GitHub 早已**不接受账号密码**；token 需要 `repo` 权限（fine-grained token 需要 `Contents: Read and write`）。

### `git push` 卡住不动

大概率是网络到 github.com 不通（国内常见）。检查：

```bash
git config --get http.proxy          # 看有没有设代理
curl -I https://github.com           # 看能否连通
```

需要走代理的话：

```bash
git config --local http.proxy http://127.0.0.1:<端口>
git config --local https.proxy http://127.0.0.1:<端口>
```

---

## 推送之后建议补的几件事

| 事项 | 怎么做 |
| --- | --- |
| 仓库 About 加描述 | 仓库首页右上角齿轮 → Description 粘贴 256 字符那版英文描述；Topics 填 `moonbit` `hackathon` `accessibility` `pose-estimation` `health` |
| 提交申报表单 | 按 `docs/05-提交物对照清单.md` 逐项打勾，仓库地址填进去 |
| 加入赛事交流群 | **未入群会影响奖金发放** |
| 录离线演示视频 | 脚本见 `docs/02-演示脚本.md`，仓库里有六张截图可以先用 |
| 把 `moon.mod` 的 name 改掉 | 仅当你要发布到 mooncakes.io 时才需要改成 `<你的用户名>/movementor`；推到 GitHub 不需要改 |
